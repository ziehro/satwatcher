package com.ziehro.satwatcher;

import android.app.PendingIntent;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.os.Build;
import android.widget.RemoteViews;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;
import androidx.work.Worker;
import androidx.work.WorkerParameters;
import androidx.annotation.NonNull;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.TimeUnit;

public class EMFWidgetProvider extends AppWidgetProvider {
    private static final String WORK_NAME = "emf_widget_update";

    @Override
    public void onUpdate(Context context, AppWidgetManager appWidgetManager, int[] appWidgetIds) {
        for (int appWidgetId : appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId);
        }
        scheduleWidgetUpdates(context);
    }

    @Override
    public void onEnabled(Context context) {
        super.onEnabled(context);
        scheduleWidgetUpdates(context);
    }

    @Override
    public void onDisabled(Context context) {
        super.onDisabled(context);
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME);
    }

    public static void updateAppWidget(Context context, AppWidgetManager appWidgetManager, int appWidgetId) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.emf_widget);

        // Load data from SharedPreferences
        SharedPreferences prefs = context.getSharedPreferences("emf_widget_data", Context.MODE_PRIVATE);
        float emfValue = prefs.getFloat("emf_value", 0.0f);
        int satCount = prefs.getInt("sat_count", 0);
        float percentLimit = prefs.getFloat("percent_limit", 0.0f);
        String nextPass = prefs.getString("next_pass", "No upcoming passes");
        String lastUpdate = prefs.getString("last_update", "--:--");

        // Update views
        views.setTextViewText(R.id.emf_value, String.format(Locale.US, "%.3f", emfValue));
        views.setTextViewText(R.id.sat_count, String.valueOf(satCount));
        views.setTextViewText(R.id.percent_limit, String.format(Locale.US, "%.4f%% of safety limit", percentLimit));
        views.setTextViewText(R.id.next_pass, "Next: " + nextPass);
        views.setTextViewText(R.id.last_update, lastUpdate);

        // Update progress bar
        int progress = Math.max(0, Math.min(100, (int) percentLimit));
        views.setProgressBar(R.id.emf_progress, 100, progress, false);

        // Set color based on exposure level
        int color;
        if (percentLimit >= 50) {
            color = Color.RED;
        } else if (percentLimit >= 25) {
            color = Color.rgb(255, 165, 0); // Orange
        } else if (percentLimit >= 10) {
            color = Color.YELLOW;
        } else {
            color = Color.rgb(76, 175, 80); // Green
        }

        // FIX: RemoteViews does not have setProgressTintList.
        // We must use setColorStateList (Requires API 31+) or ignore on older devices.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(R.id.emf_progress, "setProgressTintList", ColorStateList.valueOf(color));
        }

        // Set up click to open app
        Intent intent = new Intent(context, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        views.setOnClickPendingIntent(R.id.emf_value, pendingIntent);

        appWidgetManager.updateAppWidget(appWidgetId, views);
    }

    private static void scheduleWidgetUpdates(Context context) {
        Constraints constraints = new Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build();

        // NOTE: The minimum interval for PeriodicWorkRequest is 15 minutes.
        // 10 seconds will be automatically increased to 15 minutes by Android.
        PeriodicWorkRequest updateRequest = new PeriodicWorkRequest.Builder(
                WidgetUpdateWorker.class,
                15, TimeUnit.MINUTES
        )
                .setConstraints(constraints)
                .build();

        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.UPDATE,
                updateRequest
        );
    }

    public static class WidgetUpdateWorker extends Worker {
        public WidgetUpdateWorker(@NonNull Context context, @NonNull WorkerParameters params) {
            super(context, params);
        }

        @NonNull
        @Override
        public Result doWork() {
            calculateAndUpdateWidget();
            return Result.success();
        }

        private void calculateAndUpdateWidget() {
            Context context = getApplicationContext();
            SharedPreferences prefs = context.getSharedPreferences("emf_widget_data", Context.MODE_PRIVATE);

            // Update timestamp
            SharedPreferences.Editor editor = prefs.edit();
            editor.putString("last_update",
                    new SimpleDateFormat("HH:mm", Locale.getDefault()).format(new Date()));
            editor.apply();

            // Update all widgets
            AppWidgetManager appWidgetManager = AppWidgetManager.getInstance(context);
            int[] widgetIds = appWidgetManager.getAppWidgetIds(
                    new ComponentName(context, EMFWidgetProvider.class)
            );

            for (int widgetId : widgetIds) {
                EMFWidgetProvider.updateAppWidget(context, appWidgetManager, widgetId);
            }
        }
    }
}