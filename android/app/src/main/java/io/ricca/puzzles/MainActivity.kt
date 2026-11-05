package io.ricca.puzzles

import android.content.res.Configuration
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.lifecycleScope
import io.ricca.puzzles.ui.GameScreen
import io.ricca.puzzles.ui.HomeScreen
import io.ricca.puzzles.ui.PuzzleTheme
import io.ricca.puzzles.ui.Sheets
import io.ricca.puzzles.ui.T

class MainActivity : ComponentActivity() {
    private lateinit var c: GameController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        c = GameController(this, lifecycleScope)
        c.systemDark = isDark(resources.configuration)
        savedInstanceState?.getString("open")?.let { c.open(it) }

        setContent {
            val theme = c.theme
            LaunchedEffect(theme) {
                val light = theme != Theme.DARK
                val style = if (light) SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                            else SystemBarStyle.dark(Color.TRANSPARENT)
                enableEdgeToEdge(style, style)
                c.applyTheme()
            }
            PuzzleTheme(theme) {
                Box(Modifier.fillMaxSize().background(T.bg).safeDrawingPadding()) {
                    if (c.cur == null) HomeScreen(c) { c.open(it) }
                    else {
                        BackHandler { c.showHome() }
                        GameScreen(c) { c.showHome() }
                    }
                    Sheets(c)
                    c.toast?.let {
                        Text(it, Modifier.align(Alignment.BottomCenter).padding(bottom = 120.dp).widthIn(max = 420.dp)
                            .background(if (T.eink) androidx.compose.ui.graphics.Color.Black else T.accent, RoundedCornerShape(8.dp))
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                            color = if (T.eink) androidx.compose.ui.graphics.Color.White else T.accentText,
                            fontWeight = FontWeight.ExtraBold, fontSize = 15.sp)
                    }
                }
            }
        }
    }

    private fun isDark(cfg: Configuration) =
        cfg.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        c.systemDark = isDark(newConfig)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        c.cur?.let { outState.putString("open", it.name) }
    }

    override fun onResume() { super.onResume(); c.foreground = true }
    override fun onPause() { c.foreground = false; super.onPause() }
}
