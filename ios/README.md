# Run Teacher AI against Railway on iOS

The Railway build uses the same classroom account as the hosted web app. The iOS app signs in through the system browser using PKCE and stores its refresh token in Keychain.

1. In the Railway backend’s Auth0 tenant, select a **Native** application. Enable the classroom’s login connection, allow the Authorization Code and Refresh Token grants, and add `app.teacherai.classroom:/callback` to **Allowed Callback URLs**.
2. Copy the native application's **Client ID** and the classroom API’s **Identifier** from Auth0. The identifier must match the backend’s `Identity__Audience`. Enable **Allow Offline Access** for that API and refresh token rotation for the native client.
3. Boot an iPhone simulator or connect a development-signed iPhone. From the repository root, use `flutter devices` to find its ID, then substitute that ID and the two public Auth0 values below.

```sh
flutter run -d 'DEVICE_ID' --dart-define-from-file=ios/railway.json \
  --dart-define=OIDC_CLIENT_ID='NATIVE_CLIENT_ID' \
  --dart-define=OIDC_AUDIENCE='API_IDENTIFIER'
```

Sign in with the same account on the phone and in the hosted web app. To check sync, change a test class on one device and open **Settings → Account & sync → Sync now** on the other. A plain `flutter run` starts the local demo.
