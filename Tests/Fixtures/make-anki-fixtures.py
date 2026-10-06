#!/usr/bin/env python3
"""Builds the small Anki packages the checks read.

Invented content in the shapes real shared decks were found to have: a
vocabulary deck whose recordings read the example sentence, whose word field
carries the article and the plural, with a duplicate and two homonyms, packed the
way current Anki packs a deck for older versions (a real collection.anki21 and a
stub collection.anki2 that says "please update"); a picture deck in the oldest
format with markup, placeholders and a picture called photo.jpg!d; and a package
in the newest format, which Words cannot read and has to say so.

Run from this folder: python3 make-anki-fixtures.py
"""
import json, os, sqlite3, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))


def collection(path, models, decks, notes, cards_per_note=1):
    if os.path.exists(path):
        os.remove(path)
    db = sqlite3.connect(path)
    db.executescript("""
        create table col (id integer primary key, crt integer, mod integer, scm integer, ver integer,
            dty integer, usn integer, ls integer, conf text, models text, decks text, dconf text, tags text);
        create table notes (id integer primary key, guid text, mid integer, mod integer, usn integer,
            tags text, flds text, sfld integer, csum integer, flags integer, data text);
        create table cards (id integer primary key, nid integer, did integer, ord integer, mod integer,
            usn integer, type integer, queue integer, due integer, ivl integer, factor integer, reps integer,
            lapses integer, left integer, odue integer, odid integer, flags integer, data text);
        create table revlog (id integer primary key, cid integer, usn integer, ease integer, ivl integer,
            lastIvl integer, factor integer, time integer, type integer);
    """)
    db.execute("insert into col values (1, 0, 0, 0, 11, 0, 0, 0, '{}', ?, ?, '{}', '{}')",
               (json.dumps(models), json.dumps(decks)))
    card = 1
    for index, (mid, did, fields, tags) in enumerate(notes):
        nid = 1000 + index
        db.execute("insert into notes values (?, ?, ?, 0, 0, ?, ?, '', 0, 0, '')",
                   (nid, f"guid{index}", mid, tags, "\x1f".join(fields)))
        for ord_ in range(cards_per_note):
            db.execute("insert into cards values (?, ?, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '')",
                       (card, nid, did, ord_))
            card += 1
    db.commit()
    db.close()


def model(mid, name, fields, templates, sortf=0):
    return {
        "id": mid, "name": name, "type": 0, "sortf": sortf, "css": ".card {}",
        "flds": [{"name": f, "ord": i} for i, f in enumerate(fields)],
        "tmpls": [{"name": n, "ord": i, "qfmt": q, "afmt": a} for i, (n, q, a) in enumerate(templates)],
    }


def fake_mp3(size):
    return b"ID3\x03\x00\x00\x00\x00\x00\x00" + bytes((i * 7) % 251 for i in range(size))


def package(name, entries):
    path = os.path.join(HERE, name)
    with zipfile.ZipFile(path, "w") as archive:
        for entry, data, compressed in entries:
            archive.writestr(zipfile.ZipInfo(entry), data,
                             compress_type=zipfile.ZIP_DEFLATED if compressed else zipfile.ZIP_STORED)
    print("wrote", name, os.path.getsize(path), "bytes")


with tempfile.TemporaryDirectory() as tmp:
    # --- A vocabulary deck, packed for older versions of Anki -------------------------------
    vocab_fields = ["Note ID", "de_word", "de_sentence", "en_word", "en_sentence", "de_audio"]
    models = {
        "11": model(11, "Vocab List", vocab_fields, [
            ("Card 1", "{{de_word}} {{#de_sentence}}<i>{{de_sentence}}</i>{{/de_sentence}} {{de_audio}}",
             "{{FrontSide}}<hr id=answer>{{en_word}} <i>{{en_sentence}}</i>"),
            ("Card 2", "{{en_word}}", "{{FrontSide}}<hr id=answer>{{de_word}} {{de_audio}}"),
        ], sortf=1),
        "12": model(12, "Basic", ["Front", "Back"], [("Card 1", "{{Front}}", "{{FrontSide}}<hr id=answer>{{Back}}")]),
    }
    decks = {"1": {"id": 1, "name": "Default"}, "7": {"id": 7, "name": "Goethe"},
             "8": {"id": 8, "name": "Goethe::Kapitel 1"}}
    words = [
        ("die Ansage, -n", "Hören Sie auf die Ansage am Bahnhof.", "announcement", "Listen to the announcement."),
        ("der Arzt, -ä, e", "Der Arzt kommt.", "doctor", "The doctor is coming."),
        ("gehen", "Wir gehen morgen sehr früh zusammen ins Kino.", "to go", "We are going to the cinema."),
        ("gehen", "Ich gehe.", "to go", "I am going."),
        ("der Anschluss", "Der Anschluss ist kaputt.", "connection", "The connection is broken."),
        ("der Anschluss", "Wir haben in Mannheim einen Anschluss nach Berlin.", "connecting train", "We have a connection."),
        ("gern(e)", "Ich spiele gern Fußball mit meinen Freunden im Park.", "", "I like playing football."),
    ]
    notes, media, stored = [], {}, []
    for index, (word, sentence, meaning, translation) in enumerate(words):
        sound = f"tts-{index}.mp3"
        media[str(index)] = sound
        stored.append((str(index), fake_mp3(len(sentence) * 90), False))
        notes.append((11, 8 if index < 3 else 7,
                      [str(84886454480 + index), word, sentence, meaning, translation, f"[sound:{sound}]"], ""))
    real = os.path.join(tmp, "real.anki21")
    collection(real, models, decks, notes, cards_per_note=2)
    stub = os.path.join(tmp, "stub.anki2")
    collection(stub, {"12": models["12"]}, {"1": decks["1"]},
               [(12, 1, ["Please update to the latest Anki version, then import the .colpkg/.apkg file again.", ""], "")])
    package("legacy2-vocab.apkg", [
        ("meta", b"\x08\x02", False),
        ("collection.anki21", open(real, "rb").read(), True),
        ("collection.anki2", open(stub, "rb").read(), True),
        ("media", json.dumps(media).encode(), True),
    ] + stored)

    # --- A picture deck in the oldest format --------------------------------------------------
    picture_fields = ["Front", "Back", "Picture", "Sound", "Author", "Antonyms"]
    models = {"21": model(21, "Picture Card", picture_fields, [
        ("Card 1", "{{Front}}<br>{{Picture}}", "{{FrontSide}}<hr id=answer>{{Back}} {{Sound}}")])}
    # Three levels deep, the way a course divided into chapters and topics is:
    # deeper than Words' two.
    decks = {"1": {"id": 1, "name": "Default"}, "9": {"id": 9, "name": "Course"},
             "10": {"id": 10, "name": "Course::Chapter 1"},
             "11": {"id": 11, "name": "Course::Chapter 1::Animals"},
             "12": {"id": 12, "name": "Course::Chapter 2"}}
    jpeg = b"\xff\xd8\xff\xe0" + bytes(64)
    notes = [
        (21, 11, ["le&nbsp;chat", "<div>the <b>cat</b></div>", '<img src="cat.jpg!d">', "[sound:w0.mp3]", "Created by: Someone", "N/A"], "animals"),
        (21, 11, ["le chien", "<table><tr><td>le</td><td>the</td></tr><tr><td>chien</td><td>dog</td></tr></table>", "<img src='dog.png'>", " [sound:w1.mp3]", "Created by: Someone", "chat"], "animals"),
        (21, 12, ["la maison", "the house", "", "[sound:w2.mp3]", "Created by: Someone", "N/A"], "things"),
    ]
    old = os.path.join(tmp, "old.anki2")
    collection(old, models, decks, notes)
    png = b"\x89PNG\r\n\x1a\n" + bytes(64)
    package("legacy1-pictures.apkg", [
        ("collection.anki2", open(old, "rb").read(), True),
        ("media", json.dumps({"0": "cat.jpg!d", "1": "dog.png", "2": "w0.mp3", "3": "w1.mp3", "4": "w2.mp3"}).encode(), True),
        ("0", jpeg, False), ("1", png, False),
        ("2", fake_mp3(700), False), ("3", fake_mp3(720), False), ("4", fake_mp3(690), False),
    ])

    # --- The newest format -------------------------------------------------------------------
    package("newest.apkg", [
        ("meta", b"\x08\x03", False),
        ("collection.anki21b", bytes(range(200)), False),
        ("media", b"\x0a\x04\x0a\x02ab", False),
    ])
