<!--
  Bàn phím ảo kiểu điện thoại cho khung chat (QWERTY, giống Gboard/iOS):
    hàng 1 Q…P · hàng 2 A…L · hàng 3 Shift Z…M ⌫ · hàng 4 ?123 , 😊 🌐 [Space] . ↵
    hàng dưới cùng: 😊 | ?123 (rộng) | 🌐 VI/EN
  v-model = nội dung ô nhập (phím chèn/xoá ở CUỐI nội dung). VI gõ Telex (src/vietnameseInput.js), EN gõ thẳng.
  Emits: update:modelValue, enter (phím Enter/Gửi).
-->
<script setup>
import { ref } from 'vue'
import { composeTelex } from '../vietnameseInput'
import AppIcon from './AppIcon.vue'

const props = defineProps({ modelValue: { type: String, default: '' }, canSend: { type: Boolean, default: true } })
const emit = defineEmits(['update:modelValue', 'enter'])

const lang = ref('VI') // 'VI' | 'EN'
const mode = ref('abc') // 'abc' | 'sym' | 'sym2'
const shift = ref(false)
const emojiOpen = ref(false)

const ROWS = [
  ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
  ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
  ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
]
const SYM = [
  ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
  ['@', '#', '$', '%', '&', '-', '+', '(', ')', '/'],
  ['*', '"', "'", ':', ';', '!', '?'],
]
const SYM2 = [
  ['~', '`', '|', '•', '√', 'π', '÷', '×', '¶', '∆'],
  ['£', '¢', '€', '¥', '^', '°', '=', '{', '}', '\\'],
  ['%', '©', '®', '™', '✓', '[', ']'],
]
const EMOJIS = ['😀', '😁', '😂', '🤣', '😊', '😍', '😘', '😎', '🤔', '😅', '😢', '😭', '😡', '👍', '👎', '👏', '🙏', '💪', '👌', '✌️', '🎉', '❤️', '💔', '🔥', '⭐', '🍀', '🎁', '☕', '🍻', '🍚', '🌞', '🌧️', '📞', '💰', '✅', '❌', '⚠️', '🏆', '🎯', '🙂']

const set = (v) => emit('update:modelValue', v)
function rows() {
  return mode.value === 'abc' ? ROWS : mode.value === 'sym' ? SYM : SYM2
}
function press(k) {
  if (mode.value !== 'abc') return set(props.modelValue + k)
  const ch = shift.value ? k.toUpperCase() : k
  set(lang.value === 'VI' ? composeTelex(props.modelValue, ch) : props.modelValue + ch)
  shift.value = false
}
const typeChar = (c) => set(props.modelValue + c)
const backspace = () => set([...props.modelValue].slice(0, -1).join(''))
function toggleSym() {
  mode.value = mode.value === 'abc' ? 'sym' : 'abc'
  emojiOpen.value = false
}
function addEmoji(e) {
  set(props.modelValue + e)
}
</script>

<template>
  <div class="kb" role="group" aria-label="Bàn phím" @mousedown.prevent>
    <div v-if="emojiOpen" class="kb-emoji" role="listbox" aria-label="Biểu tượng cảm xúc">
      <button v-for="e in EMOJIS" :key="e" type="button" class="kb-emo" @click="addEmoji(e)">{{ e }}</button>
    </div>
    <template v-else>
      <div class="kb-row">
        <button v-for="k in rows()[0]" :key="k" type="button" class="kb-key" @click="press(k)">{{ mode === 'abc' && shift ? k.toUpperCase() : k }}</button>
      </div>
      <div class="kb-row kb-row2">
        <button v-for="k in rows()[1]" :key="k" type="button" class="kb-key" @click="press(k)">{{ mode === 'abc' && shift ? k.toUpperCase() : k }}</button>
      </div>
      <div class="kb-row">
        <button v-if="mode === 'abc'" type="button" class="kb-key kb-wide" :class="{ on: shift }" aria-label="Shift" :aria-pressed="shift" @click="shift = !shift">⇧</button>
        <button v-else type="button" class="kb-key kb-wide" @click="mode = mode === 'sym' ? 'sym2' : 'sym'">{{ mode === 'sym' ? '2/2' : '1/2' }}</button>
        <button v-for="k in rows()[2]" :key="k" type="button" class="kb-key" @click="press(k)">{{ mode === 'abc' && shift ? k.toUpperCase() : k }}</button>
        <button type="button" class="kb-key kb-wide" aria-label="Xoá lùi" @click="backspace">⌫</button>
      </div>
      <div class="kb-row kb-row4">
        <button type="button" class="kb-key kb-fn" @click="toggleSym">{{ mode === 'abc' ? '?123' : 'ABC' }}</button>
        <button type="button" class="kb-key" @click="typeChar(',')">,</button>
        <button type="button" class="kb-key" aria-label="Emoji" @click="emojiOpen = true">😊</button>
        <button type="button" class="kb-key" :aria-label="`Ngôn ngữ ${lang}`" @click="lang = lang === 'VI' ? 'EN' : 'VI'">🌐<small>{{ lang }}</small></button>
        <button type="button" class="kb-key kb-space" aria-label="Dấu cách" @click="typeChar(' ')">{{ mode === 'abc' ? (lang === 'VI' ? 'Tiếng Việt' : 'English') : '' }}</button>
        <button type="button" class="kb-key" @click="typeChar('.')">.</button>
        <button type="button" class="kb-key kb-enter" :disabled="!canSend" aria-label="Gửi" @click="emit('enter')">↵</button>
      </div>
    </template>

    <!-- hàng chức năng sát đáy: 😊 | ?123 (rộng) | 🌐 VI/EN -->
    <div class="kb-bottom">
      <button type="button" class="kb-key kb-b" :class="{ on: emojiOpen }" aria-label="Mở bảng emoji" @click="emojiOpen = !emojiOpen">😊</button>
      <button type="button" class="kb-key kb-b kb-num" @click="toggleSym">{{ mode === 'abc' ? '?123' : 'ABC' }}</button>
      <button type="button" class="kb-key kb-b" :aria-label="`Chuyển ngôn ngữ, đang ${lang}`" @click="lang = lang === 'VI' ? 'EN' : 'VI'">🌐 <small>{{ lang }}</small></button>
    </div>
  </div>
</template>

<style scoped>
.kb {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 8px 4px 6px;
  background: #eef2ee;
  border-radius: 12px 12px 0 0;
  user-select: none;
  -webkit-user-select: none;
}
.kb-row {
  display: flex;
  justify-content: center;
  gap: 5px;
}
.kb-row2 {
  padding: 0 4%;
}
.kb-key {
  flex: 1 1 0;
  min-width: 0;
  height: 44px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 2px;
  padding: 0;
  font: inherit;
  font-size: 18px;
  font-weight: 500;
  color: #000;
  background: #fff;
  border: 1px solid #d9e8dd;
  border-radius: 8px;
  box-shadow: 0 1px 0 rgba(0, 0, 0, 0.12);
  cursor: pointer;
}
.kb-key:active {
  background: #dcfce7;
}
.kb-key small {
  font-size: 10px;
  font-weight: 700;
  color: #15803d;
}
.kb-wide {
  flex: 1.5 1 0;
  background: #dfe6e0;
}
.kb-key.on {
  background: #16a34a;
  color: #fff;
}
.kb-fn {
  flex: 1.5 1 0;
  background: #dfe6e0;
  font-size: 14px;
}
.kb-space {
  flex: 5 1 0;
  font-size: 13px;
  color: #6b716c;
}
.kb-enter {
  flex: 1.5 1 0;
  background: #16a34a;
  color: #fff;
}
.kb-enter:disabled {
  opacity: 0.55;
}
.kb-bottom {
  display: flex;
  gap: 5px;
  padding-top: 2px;
}
.kb-b {
  flex: 1 1 0;
  height: 40px;
  background: transparent;
  border-color: transparent;
  box-shadow: none;
}
.kb-num {
  flex: 6 1 0; /* gần bằng chiều dài phím Space */
  background: #dfe6e0;
  border-radius: 10px;
  font-size: 15px;
  font-weight: 600;
}
.kb-emoji {
  display: grid;
  grid-template-columns: repeat(8, 1fr);
  gap: 2px;
  max-height: 188px;
  overflow-y: auto;
}
.kb-emo {
  height: 44px;
  font-size: 24px;
  background: none;
  border: 0;
  cursor: pointer;
}
</style>
