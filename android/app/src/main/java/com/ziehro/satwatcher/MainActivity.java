package com.ziehro.satwatcher;

import android.appwidget.AppWidgetManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;

public class MainActivity extends FlutterActivity {
    private static final String WIDGET_CHANNEL = "com.ziehro.satwatcher/widget";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), WIDGET_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if (call.method.equals("updateWidget")) {
                        // Safely extract arguments, handling nulls and converting Dart's Double to Java's float
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
    }

    private void updateWidget(float emfValue, int satCount, float percentLimit, String nextPass) {
        // 1. Save data to the specific SharedPrefs file ("emf_widget_data")
        SharedPreferences prefs = getSharedPreferences("emf_widget_data", Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();

        editor.putFloat("emf_value", emfValue);
        editor.putInt("sat_count", satCount);
        editor.putFloat("percent_limit", percentLimit);
        editor.putString("next_pass", nextPass);

        // Update the timestamp for the widget display
        editor.putString("last_update",
                new SimpleDateFormat("HH:mm", Locale.getDefault()).format(new Date()));
        editor.apply();

        // 2. Trigger widget update using the static helper method in EMFWidgetProvider
        AppWidgetManager appWidgetManager = AppWidgetManager.getInstance(this);
        int[] widgetIds = appWidgetManager.getAppWidgetIds(
                new ComponentName(this, EMFWidgetProvider.class)
        );

        for (int widgetId : widgetIds) {
            EMFWidgetProvider.updateAppWidget(this, appWidgetManager, widgetId);
        }
    }
}