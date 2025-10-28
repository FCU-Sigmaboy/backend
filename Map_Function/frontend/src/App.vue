<template>
  <div id="app">
    <!-- 顯示登入/註冊界面或地圖功能 -->
    <Auth v-if="!user" @login-success="handleLoginSuccess" />

    <div v-else class="app-container">
      <!-- 頂部導航欄 -->
      <nav class="navbar">
        <div class="nav-content">
          <h1>地理定位功能測試</h1>
          <div class="user-info">
            <span>{{ user.email }}</span>
            <button @click="handleLogout" class="logout-button">登出</button>
          </div>
        </div>
      </nav>

      <!-- 地圖功能 -->
      <div class="main-content">
        <LocationMap />
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from './supabase'
import Auth from './components/Auth.vue'
import LocationMap from './components/LocationMap.vue'

const user = ref(null)

// 檢查使用者是否已登入
onMounted(async () => {
  // 取得當前 session
  const { data: { session } } = await supabase.auth.getSession()
  user.value = session?.user ?? null

  // 監聽認證狀態變化
  supabase.auth.onAuthStateChange((_event, session) => {
    user.value = session?.user ?? null
  })
})

const handleLoginSuccess = (userData) => {
  user.value = userData
}

const handleLogout = async () => {
  const { error } = await supabase.auth.signOut()
  if (error) {
    console.error('Logout error:', error)
    alert('登出失敗：' + error.message)
  } else {
    user.value = null
  }
}
</script>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
}

#app {
  width: 100vw;
  height: 100vh;
  display: flex;
  flex-direction: column;
}

.app-container {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
}

.navbar {
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  padding: 15px 20px;
  box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
  flex-shrink: 0;
}

.nav-content {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.navbar h1 {
  font-size: 20px;
}

.user-info {
  display: flex;
  align-items: center;
  gap: 15px;
}

.user-info span {
  font-size: 14px;
  opacity: 0.9;
}

.logout-button {
  background: rgba(255, 255, 255, 0.2);
  color: white;
  border: 1px solid rgba(255, 255, 255, 0.3);
  padding: 8px 16px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 14px;
  transition: background 0.3s;
}

.logout-button:hover {
  background: rgba(255, 255, 255, 0.3);
}

.main-content {
  flex: 1;
  overflow: hidden;
  position: relative;
  min-height: 0;
}
</style>
