<template>
  <div class="auth-container">
    <div class="auth-card">
      <h2>{{ isLogin ? '登入' : '註冊' }}</h2>

      <form @submit.prevent="handleSubmit">
        <div class="form-group">
          <label for="email">Email</label>
          <input
            id="email"
            v-model="email"
            type="email"
            required
            placeholder="your@email.com"
          />
        </div>

        <div class="form-group">
          <label for="password">密碼</label>
          <input
            id="password"
            v-model="password"
            type="password"
            required
            placeholder="至少 6 個字元"
            minlength="6"
          />
        </div>

        <button type="submit" :disabled="loading" class="submit-button">
          {{ loading ? '處理中...' : (isLogin ? '登入' : '註冊') }}
        </button>
      </form>

      <p v-if="error" class="error-message">{{ error }}</p>
      <p v-if="message" class="success-message">{{ message }}</p>

      <div class="toggle-mode">
        <button @click="toggleMode" class="link-button">
          {{ isLogin ? '還沒有帳號？點此註冊' : '已有帳號？點此登入' }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { supabase } from '../supabase'

const emit = defineEmits(['login-success'])

const isLogin = ref(true)
const email = ref('')
const password = ref('')
const loading = ref(false)
const error = ref(null)
const message = ref(null)

const toggleMode = () => {
  isLogin.value = !isLogin.value
  error.value = null
  message.value = null
}

const handleSubmit = async () => {
  loading.value = true
  error.value = null
  message.value = null

  try {
    if (isLogin.value) {
      // 登入
      const { data, error: signInError } = await supabase.auth.signInWithPassword({
        email: email.value,
        password: password.value,
      })

      if (signInError) throw signInError

      message.value = '登入成功！'

      // 通知父組件登入成功
      setTimeout(() => {
        emit('login-success', data.user)
      }, 500)

    } else {
      // 註冊
      const { data, error: signUpError } = await supabase.auth.signUp({
        email: email.value,
        password: password.value,
      })

      if (signUpError) throw signUpError

      // 檢查是否需要確認郵件
      if (data.user && !data.session) {
        message.value = '註冊成功！請檢查您的郵件以確認帳號。'
      } else {
        message.value = '註冊成功！即將跳轉...'

        // 如果不需要郵件確認，自動登入
        setTimeout(() => {
          emit('login-success', data.user)
        }, 1500)
      }
    }
  } catch (err) {
    error.value = err.message || '操作失敗，請稍後再試'
    console.error('Auth error:', err)
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.auth-container {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  padding: 20px;
}

.auth-card {
  background: white;
  border-radius: 12px;
  padding: 40px;
  max-width: 400px;
  width: 100%;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.2);
}

h2 {
  text-align: center;
  color: #333;
  margin-bottom: 30px;
  font-size: 28px;
}

.form-group {
  margin-bottom: 20px;
}

label {
  display: block;
  margin-bottom: 8px;
  color: #555;
  font-weight: 500;
}

input {
  width: 100%;
  padding: 12px;
  border: 2px solid #e0e0e0;
  border-radius: 6px;
  font-size: 16px;
  transition: border-color 0.3s;
}

input:focus {
  outline: none;
  border-color: #667eea;
}

.submit-button {
  width: 100%;
  padding: 14px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  border-radius: 6px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  transition: transform 0.2s;
  margin-top: 10px;
}

.submit-button:hover:not(:disabled) {
  transform: translateY(-2px);
}

.submit-button:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.error-message {
  color: #f44336;
  margin-top: 15px;
  padding: 10px;
  background-color: #ffebee;
  border-radius: 4px;
  text-align: center;
}

.success-message {
  color: #4CAF50;
  margin-top: 15px;
  padding: 10px;
  background-color: #e8f5e9;
  border-radius: 4px;
  text-align: center;
}

.toggle-mode {
  margin-top: 20px;
  text-align: center;
}

.link-button {
  background: none;
  border: none;
  color: #667eea;
  cursor: pointer;
  font-size: 14px;
  text-decoration: underline;
}

.link-button:hover {
  color: #764ba2;
}
</style>
