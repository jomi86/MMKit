// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MMKit",
  platforms: [
    .iOS(.v18)
  ],
  products: [
    .library(
      name: "MMKitContracts",
      targets: ["MMKitContracts"]
    ),
    .library(
      name: "MMKit",
      targets: ["MMKit"]
    )
  ],
  dependencies: [
    .package(
      url: "https://github.com/firebase/firebase-ios-sdk",
      from: "12.5.0"
    ),
    .package(
      url: "https://github.com/RevenueCat/purchases-ios-spm.git",
      from: "5.0.0"
    )
  ],
  targets: [
    .target(
      name: "MMKitContracts"
    ),
    .target(
      name: "MMKit",
      dependencies: [
        "MMKitContracts",
        .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
        .product(name: "FirebaseCrashlytics", package: "firebase-ios-sdk"),
        .product(name: "RevenueCat", package: "purchases-ios-spm"),
        .product(name: "RevenueCatUI", package: "purchases-ios-spm")
      ]
    )
  ]
)
