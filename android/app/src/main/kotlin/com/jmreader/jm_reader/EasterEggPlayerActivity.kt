package com.jmreader.jm_reader

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.VideoView

/**
 * 彩蛋的全屏播放器。
 *
 * 只用系统自带的 VideoView，不引第三方库：黑底铺满、声音照放，
 * 点一下画面出「关闭」，返回键随时能退出来。
 */
class EasterEggPlayerActivity : Activity() {

    private val ui = Handler(Looper.getMainLooper())

    private var video: VideoView? = null
    private var overlay: View? = null

    /** 视频自己的分辨率，拿到之后按它算显示大小 */
    private var videoW = 0
    private var videoH = 0

    private val hideOverlay = Runnable { overlay?.visibility = View.GONE }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val path = intent.getStringExtra(EXTRA_PATH)
        if (path.isNullOrEmpty()) {
            finish()
            return
        }

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        goFullscreen()

        val player = VideoView(this)
        video = player

        val bar = buildOverlay()
        overlay = bar

        // 横屏时刘海在侧边，别让「关闭」被挡住
        bar.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                insets.displayCutout?.let { cut ->
                    view.setPadding(
                        cut.safeInsetLeft,
                        cut.safeInsetTop,
                        cut.safeInsetRight,
                        cut.safeInsetBottom,
                    )
                }
            }
            insets
        }

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(player, matchParent())
            addView(bar, matchParent())
        }

        // VideoView 会把自己缩到「刚好放得下视频」那么大，然后贴在左上角，
        // 竖着拿手机时就变成屏幕顶上的一条。这里跟着窗口尺寸重算一遍。
        root.addOnLayoutChangeListener { _, left, top, right, bottom, _, _, _, _ ->
            fitVideo(right - left, bottom - top)
        }

        // 点画面随便哪里就能唤出「关闭」，过几秒自己收起来
        player.setOnClickListener { toggleOverlay() }
        bar.setOnClickListener { toggleOverlay() }

        player.setVideoPath(path)
        player.setOnPreparedListener { media ->
            media.isLooping = false
            videoW = media.videoWidth
            videoH = media.videoHeight
            fitVideo(root.width, root.height)
            player.start()
        }
        player.setOnCompletionListener { finish() }
        player.setOnErrorListener { _, _, _ ->
            finish()
            true
        }

        setContentView(root)

        // 一进来先亮一下「关闭」和提示，省得不知道退出去
        ui.postDelayed(hideOverlay, OVERLAY_HOLD_MS)
    }

    override fun onPause() {
        ui.removeCallbacks(hideOverlay)
        video?.pause()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        video?.start()
    }

    override fun onDestroy() {
        ui.removeCallbacks(hideOverlay)
        overlay = null
        video = null
        super.onDestroy()
    }

    private fun toggleOverlay() {
        val bar = overlay ?: return
        ui.removeCallbacks(hideOverlay)
        if (bar.visibility == View.VISIBLE) {
            bar.visibility = View.GONE
        } else {
            bar.visibility = View.VISIBLE
            ui.postDelayed(hideOverlay, OVERLAY_HOLD_MS)
        }
    }

    /** 按视频本身的比例居中放到最大，不拉伸也不缩在角落里 */
    private fun fitVideo(width: Int, height: Int) {
        val player = video ?: return
        if (videoW <= 0 || videoH <= 0 || width <= 0 || height <= 0) return
        val scale = minOf(
            width.toFloat() / videoW,
            height.toFloat() / videoH,
        )
        val targetW = (videoW * scale).toInt().coerceAtLeast(1)
        val targetH = (videoH * scale).toInt().coerceAtLeast(1)
        val current = player.layoutParams as? FrameLayout.LayoutParams
        if (current != null &&
            current.width == targetW &&
            current.height == targetH
        ) {
            return
        }
        player.layoutParams = FrameLayout.LayoutParams(
            targetW,
            targetH,
            Gravity.CENTER,
        )
    }

    /** 淡淡一层遮罩 + 右上角「关闭」+ 底部一行提示 */
    private fun buildOverlay(): View {
        val close = TextView(this).apply {
            text = CLOSE_TEXT
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setPadding(dp(14), dp(8), dp(14), dp(8))
            background = GradientDrawable().apply {
                cornerRadius = dp(18).toFloat()
                setColor(0x8C000000.toInt())
                setStroke(dp(1), 0x59FFFFFF)
            }
            isClickable = true
            setOnClickListener { finish() }
        }
        val closeParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.TOP or Gravity.END,
        ).apply {
            topMargin = dp(18)
            marginEnd = dp(16)
        }

        val hint = TextView(this).apply {
            text = HINT_TEXT
            setTextColor(0xB3FFFFFF.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
        }
        val hintParams = FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
        ).apply {
            bottomMargin = dp(26)
        }

        return FrameLayout(this).apply {
            setBackgroundColor(0x26000000)
            addView(close, closeParams)
            addView(hint, hintParams)
        }
    }

    @Suppress("DEPRECATION")
    private fun goFullscreen() {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
            WindowManager.LayoutParams.FLAG_FULLSCREEN,
        )
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            )
    }

    private fun matchParent() = FrameLayout.LayoutParams(
        FrameLayout.LayoutParams.MATCH_PARENT,
        FrameLayout.LayoutParams.MATCH_PARENT,
    )

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        /** 传视频文件路径：彩蛋视频先被拷到缓存目录，再从这里放 */
        const val EXTRA_PATH = "path"

        private const val OVERLAY_HOLD_MS = 3800L
        private const val CLOSE_TEXT = "✕  关闭"
        private const val HINT_TEXT = "点一下画面唤出关闭 · 返回键也能退出"
    }
}
