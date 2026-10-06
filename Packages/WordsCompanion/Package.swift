// swift-tools-version: 6.2
import PackageDescription

// The on-device models the app can install beside Apple's own, and everything
// needed to run one: MLX to run it, Hugging Face to fetch it. Kept out of the
// app target so the app itself knows nothing of either — only of a
// `LanguageModel` it can hand to a Foundation Models session.
let package = Package(
    name: "WordsCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WordsCompanion", targets: ["WordsCompanion"]),
    ],
    dependencies: [
        // Pinned to a commit: the Foundation Models adapter is not in a
        // tagged release yet.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "c6446cf7bfb7cea76408013b614d4b2c530eaa03"),
        .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.10.2"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.4"),
    ],
    targets: [
        .target(
            name: "WordsCompanion",
            dependencies: [
                .product(name: "MLXFoundationModels", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
    ]
)
