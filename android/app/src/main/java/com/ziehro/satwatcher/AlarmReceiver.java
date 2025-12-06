// android/app/src/main/java/com/ziehro/satwatcher/AlarmReceiver.java - Replace entire file
package com.ziehro.satwatcher;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import org.json.JSONArray;
import org.json.JSONObject;

public class AlarmReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String title = intent.getStringExtra("title");
        String body = intent.getStringExtra("body");
        int notificationId = intent.getIntExtra("notificationId", 0);

        // Remove this alarm from SharedPreferences since it has fired
        removeScheduledAlarm(context, notificationId);

        NotificationManager notificationManager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    "satellite_passes",
                    "Satellite Passes",
                    NotificationManager.IMPORTANCE_HIGH
            );
            channel.setDescription("Notifications for upcoming satellite passes");
            channel.enableVibration(true);
            notificationManager.createNotificationChannel(channel);
        }

        Intent mainIntent = new Intent(context, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                context,
                0,
                mainIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, "satellite_passes")
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .setVibrate(new long[]{0, 500, 200, 500});

        notificationManager.notify(notificationId, builder.build());
    }

    private void removeScheduledAlarm(Context context, int alarmId) {
        try {
            SharedPreferences prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE
            );

            String alarmsJson = prefs.getString("flutter.scheduled_alarms", null);
            if (alarmsJson == null) return;

            JSONArray alarms = new JSONArray(alarmsJson);
            JSONArray updatedAlarms = new JSONArray();

            for (int i = 0; i < alarms.length(); i++) {
                JSONObject alarm = alarms.getJSONObject(i);
                if (alarm.getInt("id") != alarmId) {
                    updatedAlarms.put(alarm);
                }
            }

            prefs.edit()
                    .putString("flutter.scheduled_alarms", updatedAlarms.toString())
                    .apply();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}