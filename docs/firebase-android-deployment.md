# Android push and Gmail review deployment

Rumpun's Android Firebase app uses package `app.rumpun.mobile` in Firebase project `rumpun-app`.
Download its Android configuration from the Firebase console to `src/frontend/android/app/google-services.json` before building.
The file holds Google API keys, so it is kept out of Git.

## Backend setup

Apply Alembic head before starting the API and workers.
Set `RUMPUN_FIREBASE_PROJECT_ID=rumpun-app` for the push worker.
Run `python -m app.gmail_sync` about every 30 seconds to handle automatic and user-requested Gmail sync jobs promptly.
Run `python -m app.push_worker` about every 30 seconds to deliver queued notifications.
The Compose development stack defines both workers.

The push worker uses Google Application Default Credentials.
Give its workload identity the project custom role `Rumpun FCM Sender` (`projects/rumpun-app/roles/rumpunFcmSender`).
That role contains only `cloudmessaging.messages.create`, which is sufficient for the FCM HTTP v1 send endpoint.
Keep credentials outside the image and repository.
For local Docker testing, place a service account JSON file in `src/backend/firebase-credentials/service-account.json`, set `RUMPUN_GOOGLE_CREDENTIALS_DIR` to that absolute directory, and set `GOOGLE_APPLICATION_CREDENTIALS=/firebase-credentials/service-account.json` in the backend `.env`.
The credentials directory is ignored by Git.

The API stores FCM tokens per signed-in user and household.
It queues a notification when Gmail creates a new review candidate, and when a household expense category reaches 90% or 100% of its monthly budget.
New review candidates join the person's notification that is still waiting to be sent, so a large lookback sends one summary instead of one notification per email.
Notifications contain a generic message rather than email or transaction details.
The push worker checks that the candidate still needs review and that the recipient still belongs to the household before sending.

## App behavior

The Android app registers its FCM token after sign-in and household selection.
It removes the token on sign-out when the network is available.
The Gmail screen can request a lookback of 1, 2, 7, 30, or 90 days and displays the job result.
If some emails could not be classified, the job still completes and reports how many are left, and the scheduled Gmail worker retries them.
Previously seen email IDs stay excluded, including messages already ignored, reviewed, or recorded.
The review detail screen lets a person correct the transaction before posting it.

Build the phone app with its existing `.env` and the deployed API URL:

```sh
cd src/frontend
flutter build apk --release --dart-define-from-file=.env \
  --dart-define=RUMPUN_API_BASE_URL=https://your-api.example.com/api/v1
```

## Checks before launch

- Confirm the API, Gmail worker, and push worker all use the same database and project configuration.
- Confirm Google OAuth's redirect URI matches the deployed HTTPS callback.
- Confirm the Gmail OAuth consent configuration permits the intended users.
- Confirm a signed-in Android device registers one token and receives a new review notification.
- Confirm 90% and 100% budget events each notify once in a month.
- Confirm a second sync over the same days discovers zero previously seen messages.

iOS push delivery is deferred until APNs credentials are configured in Firebase.
