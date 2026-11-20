# Run Teacher AI against Railway on iOS

The Railway build uses the same classroom account as the hosted web app. The iOS app signs in through the system browser using PKCE and stores its refresh token in Keychain.

1. In the Railway backend’s Auth0 tenant, select a **Native** application. Enable the classroom’s login connection, allow the Authorization Code and Refresh Token grants, and add `app.teacherai.classroom:/callback` to **Allowed Callback URLs**.
2. The native application's public Client ID and the API identifier `https://api.teacherai.app` are in `ios/railway.json`. Grant the native app **User-Delegated Access** under the classroom API’s **Application Access** tab. Enable **Allow Offline Access** for that API and refresh token rotation for the native client.
3. Boot an iPhone simulator or connect a development-signed iPhone. From the repository root, use `flutter devices` to find its ID, then substitute it for `DEVICE_ID` below.

```sh
flutter run -d 'DEVICE_ID' --dart-define-from-file=ios/railway.json
```

Sign in with the same account on the phone and in the hosted web app. To check sync, change a test class on one device and open **Settings → Account & sync → Sync now** on the other. A plain `flutter run` starts the local demo.

## Deliver merges to TestFlight with Xcode Cloud

1. Put this revision on GitHub’s `main` branch so Apple can fetch the executable `ios/ci_scripts/ci_post_clone.sh`. The script installs Flutter 3.47.4 and prepares the Railway release configuration with Xcode Cloud’s build number.
2. With an Apple Developer Program team, select or create the iOS app in App Store Connect using the Runner bundle ID `app.teacherai.teacherAi`. Under **TestFlight → Internal Testing**, create a group and add yourself or other team testers.
3. Open `ios/Runner.xcworkspace` in Xcode. Select the **Runner** scheme and confirm the app target’s **Signing & Capabilities** shows the same team and automatic signing. Choose **Product → Xcode Cloud → Create Workflow** and connect the GitHub repository when prompted.
4. Set **Start Conditions → Branch Changes** to `main`. Add an **Archive** action for **iOS / Runner** with **Deployment Preparation → TestFlight (Internal Testing Only)**. Add a **TestFlight Internal Testing** post-action and select the group from step 2.
5. Start the first build on `main`. After Apple processes it, open TestFlight on the iPhone and accept the invitation. Subsequent merges trigger the same delivery. If App Store Connect requests export compliance information, complete it for the build.

To invite testers outside your App Store Connect team, choose **TestFlight and App Store** in the archive action and configure external testing and beta review. [Apple’s Xcode Cloud distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight)
