# Run Teacher AI against Railway on iOS

The Railway build uses the same classroom account as the hosted web app. The iOS app signs in through the system browser using PKCE and stores its refresh token in Keychain.

1. In the Railway backend’s Auth0 tenant, select a **Native** application. Enable the classroom’s login connection, allow the Authorization Code and Refresh Token grants, and add `app.teacherai.classroom:/callback` to **Allowed Callback URLs**.
2. The native application's public Client ID and the API identifier `https://api.teacherai.app` are in `ios/railway.json`. Grant the native app **User-Delegated Access** under the classroom API’s **Application Access** tab. Enable **Allow Offline Access** for that API and refresh token rotation for the native client.
3. Boot an iPhone simulator or connect a development-signed iPhone. From the repository root, use `flutter devices` to find its ID, then substitute it for `DEVICE_ID` below.

```sh
flutter run -d 'DEVICE_ID' --dart-define-from-file=ios/railway.json
```

Sign in with the same account on the phone and in the hosted web app. To check sync, change a test class on one device and open **Settings → Account & sync → Sync now** on the other. A plain `flutter run` starts the local demo.

## Deploy pushes to TestFlight

Every push to `main` triggers **Deploy iOS to TestFlight** in GitHub Actions. The workflow uploads a signed Railway build eligible for both internal and external TestFlight groups. Xcode manages the uploaded build number, including on retries. You can also start the workflow manually on `main`. [Workflow](../.github/workflows/testflight.yml)

### One-time setup

1. In App Store Connect, select or create the iOS app for bundle ID `dev.jamiewest.teacherai` on team `U352758U5C`. Under **TestFlight → Internal Testing**, create a group with **Enable automatic distribution** selected and add your testers. [Apple’s internal testing guide](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)
2. Under **Users and Access → Integrations → App Store Connect API → Team Keys**, create a dedicated team key with permission to create distribution certificates and App Store provisioning profiles and upload builds. Save the downloaded `.p8`, Key ID and Issuer ID. [Signing setup](https://docs.codemagic.io/yaml-code-signing/alternative-code-signing-methods/)
3. In GitHub’s **Settings → Environments → testflight**, set the following environment secrets. The environment for `jamiewest/teacher_ai` already allows deployments from `main` and has its certificate private key. [Environment settings](https://github.com/jamiewest/teacher_ai/settings/environments)

| Secret | Value |
| --- | --- |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID displayed above the team keys |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key ID of the dedicated team key |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Full contents of the downloaded `.p8`, including the header, footer and newlines |
| `CERTIFICATE_PRIVATE_KEY` | Existing RSA signing key used to create and reuse the distribution certificate. For a new environment, initialize it once with `openssl genrsa 2048 \| gh secret set CERTIFICATE_PRIVATE_KEY --env testflight`. |

The first run uses the signing key to obtain an Apple Distribution certificate and an App Store provisioning profile. After the upload succeeds, check the build’s processing status under **App Store Connect → TestFlight** and complete any export compliance questions Apple displays. For external testing, add the processed build to a group under **TestFlight → External Testing** and submit it for TestFlight App Review. Once approved, invite testers by email or share the group’s public link. [Apple’s external testing guide](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)

If an Xcode Cloud workflow is already configured for this repository, disable its `main` start condition when switching to GitHub Actions to avoid uploading twice.

## Optional Xcode Cloud workflow

1. Put this revision on GitHub’s `main` branch so Apple can fetch the executable `ios/ci_scripts/ci_post_clone.sh`. The script installs Flutter 3.47.4 and prepares the Railway release configuration with Xcode Cloud’s build number.
2. With an Apple Developer Program team, select or create the iOS app in App Store Connect using the Runner bundle ID `dev.jamiewest.teacherai`. Under **TestFlight → Internal Testing**, create a group and add yourself or other team testers.
3. Open `ios/Runner.xcworkspace` in Xcode. Select the **Runner** scheme and confirm the app target’s **Signing & Capabilities** shows the same team and automatic signing. Choose **Product → Xcode Cloud → Create Workflow** and connect the GitHub repository when prompted.
4. Set **Start Conditions → Branch Changes** to `main`. Add an **Archive** action for **iOS / Runner** with **Deployment Preparation → TestFlight (Internal Testing Only)**. Add a **TestFlight Internal Testing** post-action and select the group from step 2.
5. Start the first build on `main`. After Apple processes it, open TestFlight on the iPhone and accept the invitation. Subsequent merges trigger the same delivery. If App Store Connect requests export compliance information, complete it for the build.

To invite testers outside your App Store Connect team, choose **TestFlight and App Store** in the archive action and configure external testing and beta review. [Apple’s Xcode Cloud distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-xcode-cloud-builds-through-testflight)
