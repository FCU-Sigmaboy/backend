/**
 * Vue 3 應用程式進入點
 *
 * 這是整個 Vue 應用的啟動文件，包含：
 * - 使用者認證 (登入/註冊)
 * - 地理定位地圖功能
 */

import { createApp } from 'vue'
import VueGoogleMaps from '@fawmi/vue-google-maps'
import App from './App.vue'

// 建立 Vue 應用
const app = createApp(App)

// 註冊 Google Maps 插件
app.use(VueGoogleMaps, {
  load: {
    key: import.meta.env.VITE_GOOGLE_MAPS_API_KEY,
  },
})

// 掛載應用
app.mount('#app')

/**
 * 使用方式：
 *
 * 1. 完整應用模式（包含認證）：
 *    使用 App.vue，包含登入功能和地圖組件
 *
 * 2. 僅使用地圖組件（需要自行處理認證）：
 *    import LocationMap from './components/LocationMap.vue'
 *    在您的 Vue 應用中註冊並使用該組件
 *
 * 3. 僅使用認證組件：
 *    import Auth from './components/Auth.vue'
 */
