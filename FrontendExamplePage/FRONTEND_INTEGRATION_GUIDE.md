# AI 物品圖片辨識功能 - 前端整合指南

## 📋 目錄
1. [功能說明](#功能說明)
2. [快速開始](#快速開始)
3. [API 調用方式](#api-調用方式)
4. [完整範例程式碼](#完整範例程式碼)
5. [錯誤處理](#錯誤處理)
6. [UI/UX 建議](#uiux-建議)

---

## 🎯 功能說明

AI 物品圖片辨識功能可以自動分析使用者上傳的物品照片，並回傳以下資訊：
- ✅ **物品標題**（簡短、具體）
- ✅ **物品描述**（口語化，80-150字）
- ✅ **商品分類**（自動選擇最合適的分類）
- ✅ **碳足跡值**（預估值）
- ✅ **標籤**（關鍵字）
- ✅ **信心度**（0-1 之間，表示 AI 分析的可靠程度）
- ✅ **警告訊息**（如果有任何需要注意的事項）

---

## 🚀 快速開始

### 前置需求

1. **已安裝 Supabase 客戶端**
   ```bash
   npm install @supabase/supabase-js
   # 或
   yarn add @supabase/supabase-js
   ```

2. **已設定 Supabase 連接**
   ```javascript
   // src/lib/supabase.js
   import { createClient } from '@supabase/supabase-js'

   const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
   const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

   export const supabase = createClient(supabaseUrl, supabaseAnonKey)
   ```

3. **使用者已登入**（Edge Function 需要驗證）

---

## 📡 API 調用方式

### 方法 1：使用封裝好的 API 函數（推薦）

#### 步驟 1：複製 API 檔案

將 `FrontendExamplePage/analyze_itemImageAPI.js` 複製到你的專案：

```bash
# 假設你的前端專案結構是：
# src/
#   api/
#     analyze_itemImageAPI.js

cp FrontendExamplePage/analyze_itemImageAPI.js src/api/
```

#### 步驟 2：在元件中使用

```javascript
import { analyzeItemImage } from '@/api/analyze_itemImageAPI'

// 調用 AI 分析
try {
  const imageUrl = 'https://your-supabase-url/storage/v1/object/public/items/image.jpg'
  const result = await analyzeItemImage(imageUrl)

  console.log('AI 分析結果:', result)
  // result = {
  //   title: "iPhone 13 Pro 256GB",
  //   description: "去年買的 iPhone 13 Pro...",
  //   sub_category_id: 25,
  //   carbon_value: 2.5,
  //   tags: ["iPhone", "手機", "256GB"],
  //   confidence: 0.95,
  //   warnings: []
  // }
} catch (error) {
  console.error('AI 分析失敗:', error)
}
```

---

### 方法 2：直接調用 Edge Function

如果你想直接調用，不使用封裝的函數：

```javascript
import { supabase } from '@/lib/supabase'

async function analyzeImage(imageUrl) {
  // 呼叫 Edge Function
  const { data, error } = await supabase.functions.invoke('analyze-item-image', {
    body: {
      image_url: imageUrl
    }
  })

  if (error) {
    throw new Error(error.message || 'AI 分析失敗')
  }

  if (!data || !data.success) {
    throw new Error(data?.error || 'AI 分析失敗：未知錯誤')
  }

  return data.data  // 回傳分析結果
}
```

---

## 💻 完整範例程式碼

### Vue 3 完整範例

```vue
<template>
  <div class="create-listing-page">
    <!-- 圖片上傳區 -->
    <div class="image-upload">
      <input
        type="file"
        @change="handleImageUpload"
        accept="image/*"
      />
      <div v-if="uploadedImages.length > 0" class="image-preview">
        <img :src="uploadedImages[0]" alt="預覽" />
      </div>
    </div>

    <!-- AI 辨識按鈕 -->
    <div
      v-if="uploadedImages.length > 0 && !isEdit"
      class="ai-recognition-section"
    >
      <button
        @click="analyzeWithAI"
        :disabled="isAnalyzing"
        class="ai-button"
      >
        <span v-if="!isAnalyzing">✨ 使用 AI 辨識物品資訊</span>
        <span v-else>🤖 AI 辨識中...</span>
      </button>
      <p class="ai-hint">AI 會根據第一張照片自動填入商品資訊，您可以再自行調整</p>
    </div>

    <!-- 信心度顯示 -->
    <div v-if="aiConfidence > 0" class="ai-confidence">
      AI 信心度: {{ (aiConfidence * 100).toFixed(0) }}%
    </div>

    <!-- 表單 -->
    <form @submit.prevent="submitListing">
      <div class="form-group">
        <label>商品標題 *</label>
        <input
          v-model="formData.title"
          type="text"
          required
          maxlength="50"
        />
      </div>

      <div class="form-group">
        <label>商品說明 *</label>
        <textarea
          v-model="formData.description"
          required
          rows="5"
        ></textarea>
      </div>

      <div class="form-group">
        <label>商品分類 *</label>
        <select v-model="formData.sub_category_id" required>
          <option value="">請選擇分類</option>
          <option
            v-for="category in categories"
            :key="category.id"
            :value="category.id"
          >
            {{ category.main_categories.name }} > {{ category.name }}
          </option>
        </select>
      </div>

      <!-- 其他表單欄位... -->

      <button type="submit" class="submit-button">發布刊登</button>
    </form>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { supabase } from '@/lib/supabase'
import { analyzeItemImage } from '@/api/analyze_itemImageAPI'

// 狀態
const uploadedImages = ref([])
const isAnalyzing = ref(false)
const aiConfidence = ref(0)
const isEdit = ref(false) // 編輯模式不顯示 AI 按鈕

// 表單資料
const formData = ref({
  title: '',
  description: '',
  sub_category_id: null,
  carbon_value: 0,
  tags: []
})

// 分類列表（從資料庫獲取）
const categories = ref([])

// 處理圖片上傳
async function handleImageUpload(event) {
  const file = event.target.files[0]
  if (!file) return

  try {
    // 1. 上傳圖片到 Supabase Storage
    const fileName = `${Date.now()}_${file.name}`
    const { data, error } = await supabase.storage
      .from('items')
      .upload(fileName, file)

    if (error) throw error

    // 2. 獲取圖片 URL
    const { data: urlData } = supabase.storage
      .from('items')
      .getPublicUrl(fileName)

    uploadedImages.value.push(urlData.publicUrl)
    console.log('圖片上傳成功:', urlData.publicUrl)

  } catch (error) {
    console.error('圖片上傳失敗:', error)
    alert('圖片上傳失敗，請重試')
  }
}

// 使用 AI 分析圖片
async function analyzeWithAI() {
  if (uploadedImages.value.length === 0) {
    alert('請先上傳圖片')
    return
  }

  isAnalyzing.value = true

  try {
    // 呼叫 AI 分析 API
    const result = await analyzeItemImage(uploadedImages.value[0])

    console.log('✅ AI 分析成功:', result)

    // 自動填入表單
    formData.value.title = result.title
    formData.value.description = result.description
    formData.value.sub_category_id = result.sub_category_id
    formData.value.carbon_value = result.carbon_value
    formData.value.tags = result.tags || []

    // 顯示信心度
    aiConfidence.value = result.confidence

    // 顯示警告訊息（如果有）
    if (result.warnings && result.warnings.length > 0) {
      alert('提醒：\n' + result.warnings.join('\n'))
    }

    alert('✨ AI 辨識完成！請檢查並調整資訊')

  } catch (error) {
    console.error('❌ AI 分析失敗:', error)
    alert(`AI 分析失敗：${error.message}\n請手動填寫資訊`)
  } finally {
    isAnalyzing.value = false
  }
}

// 提交刊登
async function submitListing() {
  // 你的刊登邏輯...
  console.log('提交刊登:', formData.value)
}
</script>

<style scoped>
.ai-recognition-section {
  background: linear-gradient(135deg, #e3f2fd 0%, #e8f5e9 100%);
  border: 2px dashed #4caf50;
  border-radius: 12px;
  padding: 20px;
  margin: 20px 0;
  text-align: center;
}

.ai-button {
  background: linear-gradient(135deg, #4caf50 0%, #2196f3 100%);
  color: white;
  border: none;
  border-radius: 8px;
  padding: 12px 24px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.3s ease;
}

.ai-button:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(76, 175, 80, 0.4);
}

.ai-button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.ai-hint {
  margin-top: 10px;
  font-size: 14px;
  color: #666;
}

.ai-confidence {
  background: #e8f5e9;
  border-left: 4px solid #4caf50;
  padding: 10px 15px;
  margin: 10px 0;
  border-radius: 4px;
  font-weight: 600;
  color: #2e7d32;
}
</style>
```

---

### React 範例

```jsx
import { useState } from 'react'
import { supabase } from './lib/supabase'
import { analyzeItemImage } from './api/analyze_itemImageAPI'

function CreateListingPage() {
  const [uploadedImages, setUploadedImages] = useState([])
  const [isAnalyzing, setIsAnalyzing] = useState(false)
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    sub_category_id: null,
  })

  // 上傳圖片
  const handleImageUpload = async (e) => {
    const file = e.target.files[0]
    if (!file) return

    try {
      const fileName = `${Date.now()}_${file.name}`
      const { data, error } = await supabase.storage
        .from('items')
        .upload(fileName, file)

      if (error) throw error

      const { data: urlData } = supabase.storage
        .from('items')
        .getPublicUrl(fileName)

      setUploadedImages([...uploadedImages, urlData.publicUrl])
    } catch (error) {
      console.error('上傳失敗:', error)
      alert('圖片上傳失敗')
    }
  }

  // AI 分析
  const analyzeWithAI = async () => {
    if (uploadedImages.length === 0) return

    setIsAnalyzing(true)
    try {
      const result = await analyzeItemImage(uploadedImages[0])

      setFormData({
        title: result.title,
        description: result.description,
        sub_category_id: result.sub_category_id,
      })

      if (result.warnings.length > 0) {
        alert('提醒：\n' + result.warnings.join('\n'))
      }

      alert('✨ AI 辨識完成！')
    } catch (error) {
      alert(`AI 分析失敗：${error.message}`)
    } finally {
      setIsAnalyzing(false)
    }
  }

  return (
    <div className="create-listing-page">
      <input type="file" onChange={handleImageUpload} accept="image/*" />

      {uploadedImages.length > 0 && (
        <button
          onClick={analyzeWithAI}
          disabled={isAnalyzing}
        >
          {isAnalyzing ? '🤖 AI 辨識中...' : '✨ 使用 AI 辨識'}
        </button>
      )}

      <form>
        <input
          value={formData.title}
          onChange={(e) => setFormData({...formData, title: e.target.value})}
          placeholder="商品標題"
        />
        <textarea
          value={formData.description}
          onChange={(e) => setFormData({...formData, description: e.target.value})}
          placeholder="商品說明"
        />
        {/* 其他表單欄位... */}
      </form>
    </div>
  )
}
```

---

## ⚠️ 錯誤處理

### 常見錯誤與解決方案

| 錯誤訊息 | 原因 | 解決方案 |
|---------|------|---------|
| `未授權：缺少 Authorization header` | 使用者未登入 | 確保呼叫前使用者已登入 |
| `GEMINI_API_KEY 環境變數未設定` | 遠端未設定 API Key | 在 Supabase Dashboard 設定 Secret |
| `缺少 image_url 參數` | 未傳入圖片 URL | 確保圖片已上傳到 Storage |
| `無法取得圖片` | 圖片 URL 無效 | 檢查 Storage 權限和 URL |
| `AI 分析失敗` | Gemini API 錯誤 | 檢查 API Key 配額 |

### 錯誤處理範例

```javascript
async function analyzeWithAI() {
  try {
    const result = await analyzeItemImage(imageUrl)
    // 成功處理...
  } catch (error) {
    // 根據錯誤類型給予不同提示
    if (error.message.includes('未授權')) {
      alert('請先登入後再使用 AI 辨識功能')
      // 導向登入頁面
    } else if (error.message.includes('GEMINI_API_KEY')) {
      alert('AI 服務暫時無法使用，請手動填寫資訊')
      // 通知管理員
    } else if (error.message.includes('圖片')) {
      alert('圖片處理失敗，請重新上傳')
    } else {
      alert(`AI 分析失敗：${error.message}\n請手動填寫資訊`)
    }

    console.error('AI 分析錯誤詳情:', error)
  }
}
```

---

## 🎨 UI/UX 建議

### 1. **載入狀態**
```javascript
// 顯示旋轉動畫
<button disabled={isAnalyzing}>
  {isAnalyzing ? (
    <>
      <SpinnerIcon className="animate-spin" />
      AI 辨識中（3-10秒）...
    </>
  ) : (
    <>✨ 使用 AI 辨識</>
  )}
</button>
```

### 2. **進度提示**
```javascript
const [progress, setProgress] = useState(0)

// 模擬進度
const analyzeWithProgress = async () => {
  setProgress(10)
  // 上傳圖片
  setProgress(30)
  // 呼叫 AI
  setProgress(70)
  // 處理結果
  setProgress(100)
}
```

### 3. **信心度視覺化**
```jsx
<div className="confidence-bar">
  <div
    className="confidence-fill"
    style={{ width: `${confidence * 100}%` }}
  />
  <span>{(confidence * 100).toFixed(0)}% 準確度</span>
</div>
```

### 4. **可編輯提示**
```jsx
<div className="ai-result-notice">
  ✨ AI 已自動填入資訊，請檢查並調整
  <button onClick={clearAIResults}>清除 AI 結果</button>
</div>
```

---

## 📊 API 回傳格式

### 成功回應

```json
{
  "success": true,
  "data": {
    "title": "iPhone 13 Pro 256GB",
    "description": "去年買的 iPhone 13 Pro，256GB 容量，深藍色。平常都有貼保護貼和用手機殼，所以螢幕和背面都沒什麼刮痕。電池健康度還有 89%，功能都正常。因為換了新手機所以出清～",
    "sub_category_id": 25,
    "carbon_value": 2.5,
    "tags": ["iPhone", "手機", "256GB", "深藍色"],
    "confidence": 0.95,
    "warnings": []
  },
  "usage": {
    "promptTokenCount": 1234,
    "candidatesTokenCount": 256,
    "totalTokenCount": 1490
  },
  "model": "gemini-1.5-flash"
}
```

### 錯誤回應

```json
{
  "error": "AI 分析失敗",
  "message": "詳細錯誤訊息"
}
```

---

## 🔧 測試建議

### 1. **本地測試**
```javascript
// 使用測試圖片 URL
const testImageUrl = 'https://example.com/test-item.jpg'
const result = await analyzeItemImage(testImageUrl)
console.log('測試結果:', result)
```

### 2. **不同物品測試**
- ✅ 書籍（應該辨識出書名和出版資訊）
- ✅ 3C 產品（應該辨識出品牌和型號）
- ✅ 衣服（應該辨識出顏色和尺寸）
- ✅ 家具（應該辨識出家具類型和材質）

### 3. **邊界情況測試**
- ⚠️ 模糊的圖片（信心度應該較低）
- ⚠️ 多個物品在同一張圖（應該只分析主要物品）
- ⚠️ 特殊物品（應該給予警告訊息）

---

## 📞 技術支援

遇到問題？請檢查：
1. ✅ Supabase 連接是否正常
2. ✅ 使用者是否已登入
3. ✅ 圖片是否已成功上傳到 Storage
4. ✅ Edge Function 是否已部署
5. ✅ GEMINI_API_KEY 是否已在遠端設定

查看完整的測試指南：`AI_RECOGNITION_TEST.md`

查看疑難排解：`TROUBLESHOOTING.md`

---

## 🎉 完成！

現在你的前端夥伴可以輕鬆整合 AI 辨識功能了！

**重要提醒：**
- 🔑 確保遠端 Supabase 已設定 `GEMINI_API_KEY`
- 📸 圖片必須先上傳到 Storage 才能分析
- 👤 使用者必須登入才能使用此功能
- ⚡ 分析通常需要 3-10 秒
- 💰 注意 API 配額（免費版 250 次/天）
