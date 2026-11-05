package io.ricca.puzzles.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.ricca.puzzles.GameController
import io.ricca.puzzles.PUZZLES
import io.ricca.puzzles.PuzzleDef

private val Ink = Color(0xFF111111)

@Composable
fun HomeScreen(c: GameController, onOpen: (String) -> Unit) {
    val t = T
    @Suppress("UNUSED_EXPRESSION") c.homeVersion  // recompose card states after a game
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("PUZZLES", style = heavy(40, t.text).copy(letterSpacing = (-1.6).sp))
            Box(Modifier.padding(start = 3.dp, top = 12.dp).size(13.dp).background(t.pop, CircleShape).border(t.border, t.ink, CircleShape))
            Spacer(Modifier.weight(1f))
            IconSlab(Icons.Settings, "Settings", { c.sheet = io.ricca.puzzles.Sheet.Settings },
                color = t.accent, tint = t.accentText)
        }
        LazyVerticalGrid(
            GridCells.Adaptive(160.dp),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp + t.off, top = 12.dp, bottom = 28.dp),
            horizontalArrangement = Arrangement.spacedBy(18.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
            modifier = Modifier.weight(1f),
        ) {
            items(PUZZLES, key = { it.name }) { def -> Card(c, def) { onOpen(def.name) } }
            item(span = { GridItemSpan(maxLineSpan) }) {
                Text(
                    "Puzzles and generators by Simon Tatham's Portable Puzzle Collection (MIT licence).",
                    Modifier.padding(top = 14.dp).fillMaxWidth(), color = t.text2, fontFamily = Mono,
                    fontSize = 12.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, lineHeight = 19.sp,
                )
            }
        }
    }
}

@Composable
private fun Card(c: GameController, def: PuzzleDef, onClick: () -> Unit) {
    val t = T
    val (state, progress) = c.cardState(def.name)
    val fg = if (t.eink) Color.Black else Ink
    Slab(Modifier.fillMaxWidth().fillMaxHeight(), color = t.cards.getValue(def.name), onClick = onClick,
        contentAlignment = Alignment.TopStart) {
        Column(Modifier.padding(16.dp)) {
            Box(Modifier.size(64.dp).background(Color.White, RoundedCornerShape(8.dp))
                .border(t.border, Ink, RoundedCornerShape(8.dp)).padding(6.dp)) {
                PuzzleIcon(def.name, Modifier.fillMaxSize())
            }
            Spacer(Modifier.height(14.dp))
            Text(def.title.uppercase(), style = heavy(24, fg).copy(letterSpacing = (-0.7).sp, lineHeight = 24.sp))
            Text(def.tagline, color = fg, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 18.sp,
                modifier = Modifier.padding(top = 4.dp))
            Spacer(Modifier.height(14.dp))
            Text(
                state.uppercase(),
                Modifier.offset(y = 2.dp)
                    .background(if (progress) Ink else Color.White, RoundedCornerShape(4.dp))
                    .border(2.dp, Ink, RoundedCornerShape(4.dp))
                    .padding(horizontal = 7.dp, vertical = 3.dp),
                color = if (progress) Color.White else Ink, fontFamily = Mono, fontSize = 11.sp, fontWeight = FontWeight.Bold,
            )
        }
    }
}
