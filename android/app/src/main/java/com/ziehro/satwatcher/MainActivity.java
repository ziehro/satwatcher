// android/app/src/main/java/com/ziehro/satwatcher/MainActivity.java - Add alarm methods
package com.ziehro.satwatcher;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Settings;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends FlutterActivity {
    private static final String WIDGET_CHANNEL = "com.ziehro.satwatcher/widget";
    private static final String ALARM_CHANNEL = "com.ziehro.satwatcher/alarms";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        // Widget channel
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), WIDGET_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (call.method.equals("updateWidget")) {
                        Double emfValue = call.argument("emf_value");
                        Integer satCount = call.argument("sat_count");
                        Double percentLimit = call.argument("percent_limit");
                        String nextPass = call.argument("next_pass");

                        updateWidget(
                                emfValue != null ? emfValue.floatValue() : 0.0f,
                                satCount != null ? satCount : 0,
                                percentLimit != null ? percentLimit.floatValue() : 0.0f,
                                nextPass != null ? nextPass : "No upcoming passes"
                        );
                        result.success(null);
                    } else {
                        result.notImplemented();
                    }
                });

        // Alarm channel
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), ALARM_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "canScheduleExactAlarms":
                            result.success(canScheduleExactAlarms());
                            break;
                        case "openAlarmSettings":
                            openAlarmSettings();
                            result.success(null);
                            break;
                        case "scheduleAlarm":
                            Integer id = call.argument("id");
                            String title = call.argument("title");
                            String body = call.argument("body");
                            Long timestamp = call.argument("timestamp");
                            if (id != null && title != null && body != null && timestamp != null) {
                                scheduleAlarm(id, title, body, timestamp);
                                result.success(null);
                            } else {
                                result.error("INVALID_ARGS", "Missing required arguments", null);
                            }
                            break;
                        case "cancelAlarm":
                            Integer cancelId = call.argument("id");
                            if (cancelId != null) {
                                cancelAlarm(cancelId);
                                result.success(null);
                            } else {
                                result.error("INVALID_ARGS", "Missing id", null);
                            }
                            break;
                        case "cancelAllAlarms":
                            cancelAllAlarms();
                            result.success(null);
                            break;
                        default:
                            result.notImplemented();
                    }
                });
    }

    private boolean canScheduleExactAlarms() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            AlarmManager alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            return alarmManager.canScheduleExactAlarms();
        }
        return true;
    }

    private void openAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Intent intent = new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM);
            startActivity(intent);
        }
    }

    private void scheduleAlarm(int id, String title, String body, long timestamp) {
        AlarmManager alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);

        Intent intent = new Intent(this, AlarmReceiver.class);
        intent.putExtra("title", title);
        intent.putExtra("body", body);
        intent.putExtra("notificationId", id);

        PendingIntent pendingIntent = PendingIntent.getBroadcast(
                this,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (alarmManager.canScheduleExactAlarms()) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent);
            } else {
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent);
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent);
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, timestamp, pendingIntent);
        }
    }

    private void cancelAlarm(int id) {
        AlarmManager alarmManager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
        Intent intent = new Intent(this, AlarmReceiver.class);
        PendingIntent pendingIntent = PendingIntent.getBroadcast(
                this,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        alarmManager.cancel(pendingIntent);
    }

    private void cancelAllAlarms() {
        // Note: This is simplified - in production you'd want to track alarm IDs
    }

    private void updateWidget(float emfValue, int satCount, float percentLimit, String nextPass) {
        SharedPreferences prefs = getSharedPreferences("emf_widget_data", Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();

        editor.putFloat("emf_value", emfValue);
        editor.putInt("sat_count", satCount);
        editor.putFloat("percent_limit", percentLimit);
        editor.putString("next_pass", nextPass);
        editor.putString("last_update",
                new SimpleDateFormat("HH:mm", Locale.getDefault()).format(new Date()));
        editor.apply();

        AppWidgetManager appWidgetManager = AppWidgetManager.getInstance(this);
        int[] widgetIds = appWidgetManager.getAppWidgetIds(
                new ComponentName(this, EMFWidgetProvider.class)
        );

        for (int widgetId : widgetIds) {
            EMFWidgetProvider.updateAppWidget(this, appWidgetManager, widgetId);
        }
    }
}