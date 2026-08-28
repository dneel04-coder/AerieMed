package com.aerie.aerimed

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/// Home-screen widget: shows the last map snapshot + coordinates the Flutter
/// side rendered (see lib/home_widget_service.dart), and three tap targets
/// -- the map itself, "Protocols", and "8-Line/206WF" -- each deep-linking
/// back into MainActivity with a resqruck://<path> URI the Dart side routes
/// off of (HomeWidgetService.routeFor).
class ResqruckWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences
  ) {
    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.resqruck_widget).apply {
        val mapPath = widgetData.getString("map_snapshot", null)
        if (mapPath != null) {
          val bitmap = BitmapFactory.decodeFile(mapPath)
          if (bitmap != null) {
            setImageViewBitmap(R.id.widget_map, bitmap)
          }
        }

        val coords = widgetData.getString("coords", null)
        setTextViewText(R.id.widget_coords, coords ?: "Locating…")

        setOnClickPendingIntent(
            R.id.widget_map,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("resqruck://map")))
        setOnClickPendingIntent(
            R.id.widget_btn_protocols,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("resqruck://protocols")))
        setOnClickPendingIntent(
            R.id.widget_btn_8line,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse("resqruck://8line")))
      }

      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
