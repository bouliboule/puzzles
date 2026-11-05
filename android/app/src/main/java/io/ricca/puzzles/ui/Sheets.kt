package io.ricca.puzzles.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.fromHtml
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.ricca.puzzles.ConfigItem
import io.ricca.puzzles.GameController
import io.ricca.puzzles.HELP_EVERYWHERE
import io.ricca.puzzles.HelpBlock
import io.ricca.puzzles.Native
import io.ricca.puzzles.Sheet
import io.ricca.puzzles.ThemeSetting
import io.ricca.puzzles.CFG_PREFS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Sheets(c: GameController) {
    val sheet = c.sheet ?: return
    val t = T
    val close = { c.sheet = null }
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val cur = c.cur
    val title = when (sheet) {
        Sheet.Menu -> cur?.def?.title ?: ""
        Sheet.Types -> "Puzzle type"
        Sheet.Custom -> "Custom puzzle"
        Sheet.Prefs -> "${cur?.def?.title} settings"
        Sheet.GameId -> "Game ID"
        Sheet.Help -> "How to play ${cur?.def?.title}"
        Sheet.Settings -> "App settings"
    }
    ModalBottomSheet(
        onDismissRequest = close,
        sheetState = state,
        shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp),
        containerColor = t.surface,
        dragHandle = null,
        contentWindowInsets = { WindowInsets(0) },
        scrimColor = if (t.eink) Color.White.copy(alpha = .6f) else Color(0x73111111),
    ) {
        // Header band
        Row(Modifier.fillMaxWidth().background(t.accent).padding(start = 20.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically) {
            Text(title.uppercase(), Modifier.weight(1f), style = heavy(22, t.accentText))
            IconSlab(Icons.Close, "Close", close, size = 40.dp, color = Color.White, tint = Color(0xFF111111))
        }
        Box(Modifier.fillMaxWidth().height(t.border).background(t.ink))
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 12.dp)
            .navigationBarsPadding().padding(bottom = 20.dp)) {
            when (sheet) {
                Sheet.Menu -> MenuSheet(c, close)
                Sheet.Types -> TypesSheet(c, close)
                Sheet.Custom -> CustomSheet(c, close)
                Sheet.Prefs -> PrefsSheet(c, close)
                Sheet.GameId -> GameIdSheet(c, close)
                Sheet.Help -> HelpSheet(c)
                Sheet.Settings -> SettingsSheet(c)
            }
        }
    }
}

@Composable
private fun MenuItem(label: String, hint: String? = null, check: Boolean = false, onClick: () -> Unit) {
    val t = T
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clip8().clickable(onClick = onClick).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = t.text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
        if (hint != null) Text(hint, color = t.text2, fontFamily = Mono, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        if (check) Box(Modifier.size(26.dp).background(if (t.eink) Color.Black else t.accent, RoundedCornerShape(6.dp))
            .border(t.border, t.ink, RoundedCornerShape(6.dp)), contentAlignment = Alignment.Center) {
            Text("✓", color = if (t.eink) Color.White else Color(0xFF111111), fontWeight = FontWeight.Black, fontSize = 14.sp)
        }
    }
}

private fun Modifier.clip8() = this.clip(RoundedCornerShape(8.dp))

@Composable
private fun MenuSep() = Box(Modifier.padding(vertical = 8.dp).fillMaxWidth().height(T.border).background(T.ink, RoundedCornerShape(2.dp)))

@Composable
private fun MenuLabel(s: String) = Text(s.uppercase(), Modifier.padding(start = 12.dp, top = 16.dp, bottom = 4.dp),
    color = T.text2, fontFamily = Mono, fontSize = 12.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.7.sp)

@Composable
private fun MenuSheet(c: GameController, close: () -> Unit) {
    val cur = c.cur ?: return
    MenuItem("New game") { close(); c.newGame() }
    MenuItem("Restart") { close(); c.restart() }
    if (Native.canSolve(cur.engine.h) != 0) MenuItem("Solve") { close(); c.solve() }
    for (x in cur.def.extraMenu) MenuItem(x.label) { close(); c.extra(x) }
    MenuSep()
    MenuItem("Puzzle type", hint = c.label) { c.sheet = Sheet.Types }
    MenuItem("Puzzle settings") { c.sheet = Sheet.Prefs }
    MenuItem("Game ID") { c.sheet = Sheet.GameId }
    MenuItem("How to play") { c.sheet = Sheet.Help }
    MenuSep()
    MenuItem("App settings") { c.sheet = Sheet.Settings }
}

@Composable
private fun TypesSheet(c: GameController, close: () -> Unit) {
    val cur = c.cur ?: return
    val e = cur.engine
    val presets = remember(cur) { e.presets() }
    val def = cur.def.defaultParams
    if (presets.none { it.params == def }) {
        MenuItem("${e.paramsLabel(def)} (default)", check = cur.meta.params == def) { close(); c.newGame(def) }
    }
    var group: String? = null
    for (p in presets) {
        val parts = p.title.split(" / ")
        if (parts.size > 1 && parts[0] != group) { group = parts[0]; MenuLabel(group.removeSuffix("...")) }
        MenuItem(parts.last(), check = p.params == cur.meta.params) { close(); c.newGame(p.params) }
    }
    MenuSep()
    MenuItem("Custom…") { c.sheet = Sheet.Custom }
}

/** Editable form for config items; returns the live list. */
@Composable
private fun ConfigForm(items: MutableList<ConfigItem>) {
    val t = T
    Column(verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.padding(top = 8.dp)) {
        items.forEachIndexed { i, it ->
            when (it.type) {
                'b' -> Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable { items[i] = it.copy(bool = !it.bool) },
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(it.name, Modifier.weight(1f), color = t.text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                    Checkbox(it.bool)
                }
                's' -> Field(it.name) {
                    TextInput(it.text, numeric = it.text.all(Char::isDigit) && it.text.isNotEmpty()) { v -> items[i] = it.copy(text = v) }
                }
                else -> Field(it.name) { Choice(it.choices, it.choice) { v -> items[i] = it.copy(choice = v) } }
            }
        }
    }
}

@Composable
private fun Field(label: String, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(label.uppercase(), color = T.text, fontSize = 12.sp, fontWeight = FontWeight.ExtraBold, letterSpacing = 0.6.sp)
        content()
    }
}

@Composable
private fun Checkbox(on: Boolean) {
    val t = T
    Box(Modifier.size(28.dp).background(if (on) (if (t.eink) Color.Black else t.accent) else t.surface, RoundedCornerShape(6.dp))
        .border(t.border, t.ink, RoundedCornerShape(6.dp)), contentAlignment = Alignment.Center) {
        if (on) Text("✓", color = if (t.eink) Color.White else Color(0xFF111111), fontWeight = FontWeight.Black, fontSize = 16.sp)
    }
}

@Composable
private fun TextInput(value: String, numeric: Boolean = false, placeholder: String = "", onChange: (String) -> Unit) {
    val t = T
    Slab(Modifier.fillMaxWidth().height(48.dp), radius = 8.dp, shadow = 2.dp, contentAlignment = Alignment.CenterStart) {
        BasicTextField(value, onChange, Modifier.fillMaxWidth().padding(horizontal = 12.dp), singleLine = true,
            textStyle = TextStyle(color = t.text, fontSize = 17.sp, fontWeight = FontWeight.Bold),
            cursorBrush = SolidColor(t.text),
            keyboardOptions = KeyboardOptions(keyboardType = if (numeric) KeyboardType.Number else KeyboardType.Ascii, autoCorrectEnabled = false),
            decorationBox = { inner ->
                if (value.isEmpty() && placeholder.isNotEmpty()) Text(placeholder, color = t.text2, fontSize = 17.sp)
                inner()
            })
    }
}

@Composable
private fun Choice(choices: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val t = T
    var open by remember { mutableStateOf(false) }
    Box {
        Slab(Modifier.fillMaxWidth().height(48.dp), radius = 8.dp, shadow = 2.dp, onClick = { open = true },
            contentAlignment = Alignment.CenterStart) {
            Row(Modifier.padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(choices.getOrElse(selected) { "" }, Modifier.weight(1f), color = t.text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Text("▾", color = t.text, fontSize = 17.sp)
            }
        }
        DropdownMenu(open, { open = false }, containerColor = t.surface) {
            choices.forEachIndexed { i, s ->
                DropdownMenuItem({ Text(s, color = t.text, fontWeight = if (i == selected) FontWeight.Black else FontWeight.Medium) },
                    onClick = { open = false; onSelect(i) })
            }
        }
    }
}

@Composable
private fun ErrorBox(msg: String?) {
    if (msg == null) return
    Text(msg, Modifier.padding(top = 12.dp).fillMaxWidth()
        .background(if (T.eink) Color.White else Color(0xFFFF6B4A), RoundedCornerShape(6.dp))
        .border(T.border, T.ink, RoundedCornerShape(6.dp)).padding(horizontal = 10.dp, vertical = 8.dp),
        color = if (T.eink) Color.Black else Color(0xFF111111), fontWeight = FontWeight.ExtraBold, fontSize = 14.sp)
}

@Composable
private fun Actions(content: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = 16.dp, end = T.off), horizontalArrangement = Arrangement.End) { content() }
}

@Composable
private fun CustomSheet(c: GameController, close: () -> Unit) {
    val cur = c.cur ?: return
    val items = remember(cur) { mutableStateListOf(*cur.engine.paramsConfig(cur.meta.params).toTypedArray()) }
    var err by remember { mutableStateOf<String?>(null) }
    ConfigForm(items)
    ErrorBox(err)
    Actions {
        Btn("Start", primary = true) {
            cur.engine.configToParams(cur.meta.params, items)
                .onSuccess { close(); c.newGame(it) }
                .onFailure { err = it.message }
        }
    }
}

@Composable
private fun PrefsSheet(c: GameController, close: () -> Unit) {
    val cur = c.cur ?: return
    val items = remember(cur) { mutableStateListOf(*cur.engine.getConfig(CFG_PREFS).toTypedArray()) }
    var err by remember { mutableStateOf<String?>(null) }
    ConfigForm(items)
    ErrorBox(err)
    Actions { Btn("Save", primary = true) { err = c.savePrefs(items); if (err == null) close() } }
}

@Composable
private fun GameIdSheet(c: GameController, close: () -> Unit) {
    val cur = c.cur ?: return
    val t = T
    val clip = LocalClipboardManager.current
    val id = remember(cur) { Native.getId(cur.engine.h) }
    var input by remember { mutableStateOf("") }
    var err by remember { mutableStateOf<String?>(null) }
    Body("Share this ID to play the same puzzle on another device.")
    Text(id, Modifier.padding(vertical = 8.dp), color = t.text, fontFamily = Mono, fontSize = 12.sp)
    Row { Btn("Copy") { clip.setText(AnnotatedString(id)); c.toast("Copied") } }
    Spacer(Modifier.height(20.dp))
    Field("Load a game ID") { TextInput(input, placeholder = "paste ID here") { input = it } }
    ErrorBox(err)
    Actions { Btn("Load", primary = true) { err = c.loadGameId(input.trim()); if (err == null) close() } }
}

@Composable
private fun Body(s: String) = Text(s, color = T.text, fontSize = 15.sp, lineHeight = 23.sp, modifier = Modifier.padding(vertical = 6.dp))

@Composable
private fun HelpSheet(c: GameController) {
    val cur = c.cur ?: return
    val t = T
    for (b in cur.def.help + HELP_EVERYWHERE) when (b) {
        is HelpBlock.P -> Text(AnnotatedString.fromHtml(b.html), color = t.text, fontSize = 15.sp, lineHeight = 23.sp,
            modifier = Modifier.padding(vertical = 6.dp))
        is HelpBlock.H -> Text(b.text.uppercase(), color = t.text, fontSize = 15.sp, fontWeight = FontWeight.Black,
            letterSpacing = 0.5.sp, modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
        is HelpBlock.Li -> Row(Modifier.padding(vertical = 3.dp)) {
            Text("•", color = t.text, fontSize = 15.sp, lineHeight = 23.sp, modifier = Modifier.width(18.dp))
            Text(AnnotatedString.fromHtml(b.html), color = t.text, fontSize = 15.sp, lineHeight = 23.sp)
        }
    }
}

@Composable
private fun SettingsSheet(c: GameController) {
    val t = T
    val labels = mapOf(
        ThemeSetting.AUTO to "Automatic", ThemeSetting.LIGHT to "Light",
        ThemeSetting.DARK to "Dark", ThemeSetting.EINK to "E-ink (high contrast, no animation)",
    )
    val themes = ThemeSetting.entries
    Column(verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.padding(top = 8.dp)) {
        Field("Theme") {
            Choice(themes.map { labels.getValue(it) }, themes.indexOf(c.themeSetting)) { c.updateSettings(theme = themes[it]) }
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable { c.updateSettings(longPress = !c.longPress) },
            verticalAlignment = Alignment.CenterVertically) {
            Text("Long press for secondary action", Modifier.weight(1f), color = t.text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            Checkbox(c.longPress)
        }
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable { c.updateSettings(showTimer = !c.showTimer) },
            verticalAlignment = Alignment.CenterVertically) {
            Text("Show timer", Modifier.weight(1f), color = t.text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            Checkbox(c.showTimer)
        }
    }
    Text("Puzzle engine: Simon Tatham's Portable Puzzle Collection, compiled natively. MIT licence.",
        Modifier.padding(top = 22.dp), color = t.text2, fontSize = 13.sp)
}
