# Firebase Setup Guide for S758 Garage App

## Prerequisites
- Google Account
- Flutter SDK installed
- Android Studio or VS Code

## Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Add project"**
3. Enter project name: `s758-garage-app`
4. Disable Google Analytics (optional for this app)
5. Click **"Create project"**

## Step 2: Enable Email/Password Authentication

1. In Firebase Console, go to **Authentication** > **Sign-in method**
2. Click **"Email/Password"**
3. Enable **"Email/Password"** (first toggle)
4. Click **"Save"**

## Step 3: Add Android App to Firebase

1. In Firebase Console, click the **Android icon** to add an Android app
2. Enter the package name: `com.example.garage_app`
   - (Or your custom package name if you changed it)
3. Enter app nickname: `S758 Garage App`
4. Skip the SHA-1 certificate (optional for basic auth)
5. Click **"Register app"**

## Step 4: Download Configuration File

1. Download `google-services.json`
2. Place it in: `android/app/google-services.json`
3. **IMPORTANT**: Do not commit this file to public repositories

## Step 5: Create User Accounts

Since this is an admin-managed app (no self-registration):

1. Go to **Authentication** > **Users**
2. Click **"Add user"**
3. Enter email and password for each authorized user
4. Users will use these credentials to log in

## Step 6: Verify Setup

After completing the setup:

1. Run `flutter pub get`
2. Run `flutter run`
3. Try logging in with a created user account
4. Check Firebase Console > Authentication > Users to see sign-in activity

## Troubleshooting

### "No Firebase App" Error
- Ensure `google-services.json` is in `android/app/`
- Run `flutter clean && flutter pub get`

### "Invalid credentials" Error
- Verify the email/password in Firebase Console
- Check if the user account is enabled

### Build Errors
- Ensure minSdk is set to 21 or higher
- Verify Google Services plugin is applied correctly

## Security Notes

1. **Never commit `google-services.json` to public repos**
2. Add to `.gitignore`:
   ```
   android/app/google-services.json
   ```
3. Share the file securely with team members

## File Structure After Setup

```
android/
├── app/
│   ├── google-services.json  <- Downloaded from Firebase
│   ├── build.gradle.kts
│   └── src/main/AndroidManifest.xml
└── build.gradle.kts
```
