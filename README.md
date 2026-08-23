# BloomRecipe

Native SwiftUI iOS app: photograph a coffee bag, generate an xBloom Studio Omni Dripper recipe, and create that recipe in **your** official xBloom app.

xBloom does not publish a recipe API. BloomRecipe signs into your own xBloom account using the community-published unofficial cloud protocol (same approach as [xbloom-ble](https://github.com/Janczykkkko/xbloom-ble) and [pourpilot](https://github.com/hgstrm/pourpilot)). That connection can break if xBloom changes their servers. The app never starts a brew and never talks to the machine over Bluetooth.

## What you need

- A Mac with Xcode 16
- An iPhone (camera) and the official xBloom app
- Your xBloom account email and password
- An OpenAI API key (GPT-4o vision)

This project was authored on Windows. Open it on a Mac to build, run tests, and install on a phone.

## Open and run

1. Copy `BloomRecipe/` to a Mac.
2. Open `BloomRecipe.xcodeproj` in Xcode.
3. Select your Team under **Signing & Capabilities**.
4. Run on an iPhone (the simulator has no camera; the photo library still works).
5. In **Settings**, add the OpenAI key and xBloom login, then tap **Sign in**.
6. On **Scan**, photograph the bag front (back optional) and tap **Read the bag**.
7. Check the extracted profile, generate the recipe, then tap **Create in xBloom**.
8. Open the official xBloom app → **My Recipes**. Look for names starting with `BloomRecipe ·`.

## Recipe rules

The engine builds a valid Studio recipe first, then optionally asks the model for small adjustments:

- Light washed coffees: hotter water, longer bloom, four pours
- Dark / natural coffees: coarser grind, cooler water, three pours
- Hard limits: dose 5–18 g, grind 1–80, 40–95 °C, flow 3.0–3.5 ml/s, RPM 60–120

## Tests

On a Mac:

```bash
xcodebuild -scheme BloomRecipe -destination 'platform=iOS Simulator,name=iPhone 16' test
```

## Privacy

Keys and the xBloom password stay in the iOS Keychain. Photos are sent only to OpenAI when you analyze a bag. Recipe payloads are sent only to xBloom when you tap **Create in xBloom**.
