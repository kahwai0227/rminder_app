package com.example.rminder_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

class QuickAddWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.widget_quick_add).apply {
                setTextViewText(R.id.widget_title, "Quick Add")

                // Category name from stored categories_json + cat_index
                val categoriesJson = widgetData.getString("categories_json", null)
                val catIndex = widgetData.getInt("cat_index", 0)
                val catName = getCategoryName(categoriesJson, catIndex)
                setTextViewText(R.id.txt_category, catName ?: "Select")

                // Quick category buttons: first three categories for fast selection
                run {
                    val arr = runCatching { JSONArray(categoriesJson ?: "[]") }.getOrElse { JSONArray() }
                    val total = arr.length()
                    val quickIds = intArrayOf(R.id.btn_quick_cat_1, R.id.btn_quick_cat_2, R.id.btn_quick_cat_3)
                    var shown = 0
                    val end = minOf(3, total)
                    for (i in 0 until end) {
                        val obj = arr.getJSONObject(i)
                        val name = obj.optString("name", "")
                        val btnId = quickIds[shown]
                        setTextViewText(btnId, name)
                        val intent = HomeWidgetBackgroundIntent.getBroadcast(
                            context, Uri.parse("rminder://widget?action=cat_select&index=$i")
                        )
                        setOnClickPendingIntent(btnId, intent)
                        setViewVisibility(btnId, android.view.View.VISIBLE)
                        shown++
                    }
                    for (j in shown until quickIds.size) {
                        setViewVisibility(quickIds[j], android.view.View.GONE)
                    }
                }

                // Amount string
                val amountStr = widgetData.getString("amount_str", "") ?: ""
                setTextViewText(R.id.txt_amount, if (amountStr.isEmpty()) "0.00" else amountStr)

                // No note in this version

                // Populate category list panel when visible
                val listVisible = widgetData.getInt("cat_list_visible", 0) == 1
                setViewVisibility(R.id.cat_list_panel, if (listVisible) android.view.View.VISIBLE else android.view.View.GONE)
                if (listVisible) {
                    val arr = runCatching { JSONArray(categoriesJson ?: "[]") }.getOrElse { JSONArray() }
                    val total = arr.length()
                    val ids = intArrayOf(
                        R.id.btn_cat_item_1,
                        R.id.btn_cat_item_2,
                        R.id.btn_cat_item_3,
                        R.id.btn_cat_item_4,
                        R.id.btn_cat_item_5,
                        R.id.btn_cat_item_6,
                        R.id.btn_cat_item_7,
                        R.id.btn_cat_item_8,
                        R.id.btn_cat_item_9,
                        R.id.btn_cat_item_10
                    )

                    var btnIdx = 0
                    val end = minOf(total, ids.size)
                    for (i in 0 until end) {
                        val obj = arr.getJSONObject(i)
                        val name = obj.optString("name", "")
                        val btnId = ids[btnIdx]
                        setTextViewText(btnId, name)
                        val intent = HomeWidgetBackgroundIntent.getBroadcast(
                            context, Uri.parse("rminder://widget?action=cat_select&index=$i")
                        )
                        setOnClickPendingIntent(btnId, intent)
                        setViewVisibility(btnId, android.view.View.VISIBLE)
                        btnIdx++
                    }
                    // Hide remaining
                    for (j in btnIdx until ids.size) {
                        setViewVisibility(ids[j], android.view.View.GONE)
                    }
                }

                // Wire category prev/next

                // Category select (toggle list visibility via background action)
                setOnClickPendingIntent(
                    R.id.btn_cat_select,
                    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("rminder://widget?action=cat_toggle"))
                )

                // Wire keypad buttons
                fun keyIntent(v: String) = HomeWidgetBackgroundIntent.getBroadcast(
                    context, Uri.parse("rminder://widget?action=key&value=$v")
                )
                setOnClickPendingIntent(R.id.btn_k1, keyIntent("1"))
                setOnClickPendingIntent(R.id.btn_k2, keyIntent("2"))
                setOnClickPendingIntent(R.id.btn_k3, keyIntent("3"))
                setOnClickPendingIntent(R.id.btn_k4, keyIntent("4"))
                setOnClickPendingIntent(R.id.btn_k5, keyIntent("5"))
                setOnClickPendingIntent(R.id.btn_k6, keyIntent("6"))
                setOnClickPendingIntent(R.id.btn_k7, keyIntent("7"))
                setOnClickPendingIntent(R.id.btn_k8, keyIntent("8"))
                setOnClickPendingIntent(R.id.btn_k9, keyIntent("9"))
                setOnClickPendingIntent(R.id.btn_k0, keyIntent("0"))
                setOnClickPendingIntent(R.id.btn_k00, keyIntent("00"))

                // Clear, backspace, note cycle, save
                setOnClickPendingIntent(
                    R.id.btn_clear,
                    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("rminder://widget?action=clear"))
                )
                setOnClickPendingIntent(
                    R.id.btn_backspace,
                    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("rminder://widget?action=backspace"))
                )
                // Note cycling removed
                setOnClickPendingIntent(
                    R.id.btn_save,
                    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("rminder://widget?action=save"))
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun getCategoryName(categoriesJson: String?, index: Int): String? {
        if (categoriesJson.isNullOrEmpty()) return null
        return runCatching {
            val arr = JSONArray(categoriesJson)
            if (arr.length() == 0) return null
            val i = ((index % arr.length()) + arr.length()) % arr.length()
            val obj = arr.getJSONObject(i)
            obj.getString("name")
        }.getOrNull()
    }
}
