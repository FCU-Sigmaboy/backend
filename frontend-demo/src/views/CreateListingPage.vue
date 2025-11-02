<template>
  <div class="create-listing-page">
    <AppHeader :user-points="userPoints" />

    <main class="main-content">
      <div class="create-container">
        <!-- Page Header -->
        <div class="page-header">
          <button class="back-btn" @click="goBack">
            <i class="bi bi-arrow-left"></i>
          </button>
          <h1 class="page-title">{{ isEdit ? '編輯刊登' : '刊登物品' }}</h1>
          <div class="spacer"></div>
        </div>

        <!-- Create Form -->
        <div class="form-card">
          <form @submit.prevent="handleSubmit">
            <!-- Image Upload Section -->
            <div class="form-section">
              <label class="section-label">
                商品照片 <span class="required">*</span>
              </label>
              <p class="section-hint">最多上傳 8 張照片，第一張為封面照片</p>

              <div class="image-upload-grid">
                <!-- Uploaded Images -->
                <div
                  v-for="(image, index) in formData.images"
                  :key="index"
                  class="image-item"
                >
                  <img :src="image" alt="Product Image" class="uploaded-image" />
                  <button
                    type="button"
                    class="remove-image-btn"
                    @click="removeImage(index)"
                  >
                    <i class="bi bi-x-circle-fill"></i>
                  </button>
                  <span v-if="index === 0" class="cover-badge">封面</span>
                </div>

                <!-- Upload Button -->
                <button
                  v-if="formData.images.length < 8"
                  type="button"
                  class="upload-placeholder"
                  @click="triggerImageInput"
                >
                  <i class="bi bi-plus-circle"></i>
                  <span>上傳照片</span>
                </button>
              </div>

              <input
                ref="imageInput"
                type="file"
                accept="image/*"
                multiple
                style="display: none"
                @change="handleImageUpload"
              />

              <!-- 【新增 2025-11-02】AI 自動填寫按鈕 -->
              <button
                v-if="formData.images.length > 0"
                type="button"
                class="ai-analyze-btn"
                :disabled="isAnalyzing"
                @click="analyzeWithAI"
              >
                <i class="bi bi-stars"></i>
                <span v-if="!isAnalyzing">🤖 AI 自動填寫</span>
                <span v-else>🤖 AI 分析中...</span>
              </button>

              <!-- 【新增 2025-11-02】AI 警告訊息 -->
              <div v-if="aiWarnings.length > 0" class="ai-warnings">
                <div class="warning-header">
                  <i class="bi bi-exclamation-triangle-fill"></i>
                  <span>AI 分析提示</span>
                </div>
                <ul class="warning-list">
                  <li v-for="(warning, index) in aiWarnings" :key="index">
                    {{ warning }}
                  </li>
                </ul>
              </div>
            </div>

            <!-- Title Field -->
            <div class="form-section">
              <label for="title" class="form-label">
                商品標題 <span class="required">*</span>
              </label>
              <input
                id="title"
                v-model="formData.title"
                type="text"
                class="form-input"
                placeholder="請輸入商品標題"
                maxlength="100"
                required
              />
              <p class="char-count">{{ formData.title.length }}/100</p>
            </div>

            <!-- Category Field -->
            <div class="form-section">
              <label for="category" class="form-label">
                商品分類 <span class="required">*</span>
              </label>
              <select
                id="category"
                v-model="formData.category"
                class="form-select"
                required
              >
                <option value="">{{ isLoadingCategories ? '載入中...' : '請選擇分類' }}</option>
                <option
                  v-for="cat in categories"
                  :key="cat.id"
                  :value="String(cat.id)"
                >
                  {{ cat.name }}
                </option>
              </select>
            </div>

            <!-- Description Field -->
            <div class="form-section">
              <label for="description" class="form-label">
                商品說明 <span class="required">*</span>
              </label>
              <textarea
                id="description"
                v-model="formData.description"
                class="form-textarea"
                rows="6"
                placeholder="請詳細描述商品狀況、使用情形等..."
                maxlength="1000"
                required
              ></textarea>
              <p class="char-count">{{ formData.description.length }}/1000</p>
            </div>

            <!-- Price Field -->
            <div class="form-section">
              <label for="price" class="form-label">
                價格 <span class="required">*</span>
              </label>
              <div class="price-input-wrapper">
                <span class="currency-symbol">NT$</span>
                <input
                  id="price"
                  v-model.number="formData.price"
                  type="number"
                  class="form-input price-input"
                  placeholder="0"
                  min="0"
                  required
                />
              </div>
              <div class="checkbox-group">
                <label class="checkbox-label">
                  <input
                    v-model="formData.isFree"
                    type="checkbox"
                    class="checkbox-input"
                    @change="handleFreeChange"
                  />
                  <span class="checkbox-text">免費贈送</span>
                </label>
                <label class="checkbox-label">
                  <input
                    v-model="formData.isNegotiable"
                    type="checkbox"
                    class="checkbox-input"
                  />
                  <span class="checkbox-text">可議價</span>
                </label>
              </div>
            </div>

            <!-- Condition Field -->
            <div class="form-section">
              <label class="form-label">
                商品狀況 <span class="required">*</span>
              </label>
              <div class="condition-options">
                <label
                  v-for="condition in conditions"
                  :key="condition.value"
                  :class="['condition-option', { active: formData.condition === condition.value }]"
                >
                  <input
                    v-model="formData.condition"
                    type="radio"
                    :value="condition.value"
                    class="condition-radio"
                    required
                  />
                  <span class="condition-label">{{ condition.label }}</span>
                </label>
              </div>
            </div>

            <!-- Location Field -->
            <div class="form-section">
              <label for="location" class="form-label">
                交易地點 <span class="required">*</span>
              </label>
              <select
                id="location"
                v-model="formData.location"
                class="form-select"
                required
              >
                <option value="">請選擇地區</option>
                <option value="中區">台中市中區</option>
                <option value="東區">台中市東區</option>
                <option value="南區">台中市南區</option>
                <option value="西區">台中市西區</option>
                <option value="北區">台中市北區</option>
                <option value="西屯區">台中市西屯區</option>
                <option value="南屯區">台中市南屯區</option>
                <option value="北屯區">台中市北屯區</option>
                <option value="豐原區">台中市豐原區</option>
                <option value="大里區">台中市大里區</option>
                <option value="太平區">台中市太平區</option>
                <option value="沙鹿區">台中市沙鹿區</option>
              </select>
            </div>

            <!-- Trade Method Field -->
            <div class="form-section">
              <label class="form-label">
                交易方式 <span class="required">*</span>
              </label>
              <div class="checkbox-group">
                <label class="checkbox-label">
                  <input
                    v-model="formData.tradeMethods.meetup"
                    type="checkbox"
                    class="checkbox-input"
                  />
                  <span class="checkbox-text">面交</span>
                </label>
                <label class="checkbox-label">
                  <input
                    v-model="formData.tradeMethods.delivery"
                    type="checkbox"
                    class="checkbox-input"
                  />
                  <span class="checkbox-text">郵寄/宅配</span>
                </label>
              </div>
            </div>

            <!-- Form Actions -->
            <div class="form-actions">
              <button type="button" class="cancel-btn" @click="goBack">
                取消
              </button>
              <button type="submit" class="publish-btn" :disabled="isSubmitting">
                <span v-if="!isSubmitting">
                  {{ isEdit ? '更新刊登' : '發布刊登' }}
                </span>
                <span v-else>
                  <i class="bi bi-arrow-repeat spin"></i>
                  {{ isEdit ? '更新中...' : '發布中...' }}
                </span>
              </button>
            </div>
          </form>
        </div>
      </div>
    </main>

    <AppFooter />
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import AppHeader from '../components/AppHeader.vue';
import AppFooter from '../components/AppFooter.vue';
import { analyzeItemImage } from '../api/analyzeItemImageAPI'; // 【新增 2025-11-02】AI 分析 API
import { supabase } from '../lib/supabase'; // 【新增 2025-11-02】上傳圖片用

const route = useRoute();
const router = useRouter();

// State
const userPoints = ref(500);
const isEdit = ref(!!route.params.id);
const isSubmitting = ref(false);
const imageInput = ref(null);

// 【新增 2025-11-02】AI 相關狀態
const isAnalyzing = ref(false);
const aiWarnings = ref([]);
const uploadedImageUrls = ref([]); // 儲存上傳到 Supabase Storage 的 URL

// 【新增 2025-11-02】分類資料
const categories = ref([]);
const isLoadingCategories = ref(false);

const formData = ref({
  images: [],
  title: '',
  category: '',  // main_category_id (用於顯示)
  subcategoryId: null,  // sub_category_id (用於發布)
  description: '',
  price: 0,
  isFree: false,
  isNegotiable: false,
  condition: '',
  location: '',
  carbonFootprint: 0,
  tags: [],
  tradeMethods: {
    meetup: false,
    delivery: false
  }
});

const conditions = [
  { value: '全新', label: '全新' },
  { value: '近全新', label: '近全新' },
  { value: '良好', label: '良好' },
  { value: '普通', label: '普通' },
  { value: '需修理', label: '需修理' }
];

// Methods
const goBack = () => {
  router.back();
};

const triggerImageInput = () => {
  imageInput.value.click();
};

// 【新增 2025-11-02】載入分類資料
const loadCategories = async () => {
  isLoadingCategories.value = true;
  try {
    const { data, error } = await supabase
      .from('main_categories')
      .select('id, name')
      .order('id');

    if (error) throw error;
    categories.value = data || [];
    console.log('分類載入成功:', categories.value);
  } catch (error) {
    console.error('載入分類失敗:', error);
    alert('載入分類失敗，請重新整理頁面');
  } finally {
    isLoadingCategories.value = false;
  }
};

// 【新增 2025-11-02】頁面載入時執行
onMounted(() => {
  loadCategories();
});

// 【修改 2025-11-02】上傳圖片到 Supabase Storage
const handleImageUpload = async (event) => {
  const files = Array.from(event.target.files);
  const remainingSlots = 8 - formData.value.images.length;
  const filesToProcess = files.slice(0, remainingSlots);

  for (const file of filesToProcess) {
    // 1. 建立預覽 (DataURL)
    const reader = new FileReader();
    reader.onload = (e) => {
      formData.value.images.push(e.target.result);
    };
    reader.readAsDataURL(file);

    // 2. 上傳到 Supabase Storage
    try {
      // 取得檔案副檔名
      const fileExt = file.name.split('.').pop();
      // 使用 timestamp + 隨機數作為檔名，避免中文字元問題
      const fileName = `${Date.now()}_${Math.random().toString(36).substring(7)}.${fileExt}`;
      const { data, error } = await supabase.storage
        .from('items')
        .upload(fileName, file);

      if (error) {
        console.error('圖片上傳失敗:', error);
        alert(`圖片上傳失敗: ${error.message}`);
        continue;
      }

      // 3. 取得公開 URL
      const { data: { publicUrl } } = supabase.storage
        .from('items')
        .getPublicUrl(fileName);

      uploadedImageUrls.value.push(publicUrl);
      console.log('圖片已上傳:', publicUrl);

    } catch (error) {
      console.error('上傳過程發生錯誤:', error);
    }
  }

  // Clear input
  event.target.value = '';
};

// 【修改 2025-11-02】同時移除預覽和上傳的 URL
const removeImage = (index) => {
  formData.value.images.splice(index, 1);
  uploadedImageUrls.value.splice(index, 1);
};

// 【新增 2025-11-02】AI 自動填寫功能
const analyzeWithAI = async () => {
  if (uploadedImageUrls.value.length === 0) {
    alert('請先上傳圖片');
    return;
  }

  isAnalyzing.value = true;
  aiWarnings.value = [];

  try {
    console.log('[AI分析] 開始分析第一張圖片:', uploadedImageUrls.value[0]);

    // 呼叫 AI 分析 API
    const result = await analyzeItemImage(uploadedImageUrls.value[0]);

    if (result.success && result.data) {
      const aiData = result.data;

      // 自動填入標題
      if (aiData.title) {
        formData.value.title = aiData.title;
      }

      // 自動填入描述
      if (aiData.description) {
        formData.value.description = aiData.description;
      }

      // 自動填入分類和碳足跡
      if (aiData.sub_category_id) {
        // 儲存 sub_category_id
        formData.value.subcategoryId = aiData.sub_category_id;

        // 查詢 sub_category 的 main_category_id 用於顯示
        const { data: subCat, error: subCatError } = await supabase
          .from('sub_categories')
          .select('main_category_id')
          .eq('id', aiData.sub_category_id)
          .single();

        if (!subCatError && subCat) {
          formData.value.category = String(subCat.main_category_id);
          console.log(`[AI分析] 分類已設定: main_category_id=${subCat.main_category_id}, sub_category_id=${aiData.sub_category_id}`);
        } else {
          console.warn('[AI分析] 無法查詢分類:', subCatError);
        }
      }

      // 自動填入碳足跡
      if (aiData.carbon_value) {
        formData.value.carbonFootprint = aiData.carbon_value;
      }

      // 自動填入標籤
      if (aiData.tags && aiData.tags.length > 0) {
        formData.value.tags = aiData.tags;
      }

      // 顯示警告訊息
      if (aiData.warnings && aiData.warnings.length > 0) {
        aiWarnings.value = aiData.warnings;
      }

      // 顯示成功訊息
      alert(`AI 分析完成！\n信心度: ${(aiData.confidence * 100).toFixed(0)}%\n碳足跡: ${aiData.carbon_value} kg`);

      console.log('[AI分析] 分析成功:', result);
    } else {
      throw new Error(result.error || 'AI 分析失敗');
    }

  } catch (error) {
    console.error('[AI分析] 失敗:', error);
    alert(`AI 分析失敗: ${error.message}`);
  } finally {
    isAnalyzing.value = false;
  }
};

const handleFreeChange = () => {
  if (formData.value.isFree) {
    formData.value.price = 0;
    formData.value.isNegotiable = false;
  }
};

const handleSubmit = async () => {
  // Validate images
  if (uploadedImageUrls.value.length === 0) {
    alert('請至少上傳一張商品照片');
    return;
  }

  // Validate required fields
  if (!formData.value.title || !formData.value.description) {
    alert('請填寫標題和描述');
    return;
  }

  if (!formData.value.category) {
    alert('請選擇分類');
    return;
  }

  if (!formData.value.condition) {
    alert('請選擇物品狀況');
    return;
  }

  if (!formData.value.price || formData.value.price <= 0) {
    alert('請設定價格');
    return;
  }

  // Validate trade methods
  if (!formData.value.tradeMethods.meetup && !formData.value.tradeMethods.delivery) {
    alert('請至少選擇一種交易方式');
    return;
  }

  isSubmitting.value = true;

  try {
    // 1. 取得使用者資訊
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      throw new Error('請先登入');
    }

    // 2. 取得或建立使用者的 location
    let userLocationId = null;
    const { data: locations, error: locationError } = await supabase
      .from('locations')
      .select('id')
      .eq('user_id', user.id)
      .eq('is_primary', true)
      .limit(1);

    if (locationError) {
      console.error('查詢 location 失敗:', locationError);
    }

    if (locations && locations.length > 0) {
      userLocationId = locations[0].id;
    } else {
      // 如果沒有 primary location，取第一個
      const { data: anyLocation } = await supabase
        .from('locations')
        .select('id')
        .eq('user_id', user.id)
        .limit(1);

      if (anyLocation && anyLocation.length > 0) {
        userLocationId = anyLocation[0].id;
      } else {
        // 建立一個預設 location（使用台北101座標）
        // 使用 PostGIS POINT 格式
        const { data: newLocation, error: createLocationError } = await supabase
          .from('locations')
          .insert({
            user_id: user.id,
            coordinates: 'POINT(121.5654 25.0330)',
            type: '其他',
            is_primary: true,
            formatted_address: '台北市信義區'
          })
          .select('id')
          .single();

        if (createLocationError) {
          console.error('建立 location 失敗:', createLocationError);
          throw new Error(`建立位置資訊失敗: ${createLocationError.message}`);
        }

        userLocationId = newLocation.id;
      }
    }

    console.log('使用 location ID:', userLocationId);

    // 3. 呼叫 create_item RPC 函數
    // 使用 subcategoryId（AI 填入）或 category（手動選擇，預設為主分類）
    const subCategoryId = formData.value.subcategoryId || parseInt(formData.value.category);

    const { data, error } = await supabase.rpc('create_item', {
      p_sub_category_id: subCategoryId,
      p_user_location_id: userLocationId,
      p_title: formData.value.title,
      p_description: formData.value.description,
      p_condition: formData.value.condition,
      p_price: parseInt(formData.value.price),
      p_carbon_value: formData.value.carbonFootprint || 0,
      p_image_urls: uploadedImageUrls.value,
      p_tags: formData.value.tags || []
    });

    if (error) {
      console.error('建立物品失敗:', error);
      throw new Error(error.message);
    }

    console.log('物品建立成功:', data);

    // Show success message
    alert(isEdit.value ? '刊登已更新！' : '刊登成功！');

    // Navigate to profile or listing detail
    router.push({ name: 'UserProfile' });
  } catch (error) {
    console.error('Error creating listing:', error);
    alert(`刊登失敗: ${error.message}`);
  } finally {
    isSubmitting.value = false;
  }
};
</script>

<style scoped lang="scss">
@import '@/styles/variables';

.create-listing-page {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: #f9f9f9;
}

.main-content {
  flex: 1;
  padding: 30px 0 60px;
}

.create-container {
  max-width: 900px;
  margin: 0 auto;
  padding: 0 20px;
}

// Page Header
.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 30px;

  .back-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border: none;
    background: white;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.3s;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.08);

    i {
      font-size: 20px;
      color: #1e1e1e;
    }

    &:hover {
      background: #f5f5f5;
      transform: translateX(-3px);
    }
  }

  .page-title {
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 28px;
    font-weight: 700;
    color: #1e1e1e;
    margin: 0;
  }

  .spacer {
    width: 40px;
  }
}

// Form Card
.form-card {
  background: white;
  border-radius: 12px;
  padding: 40px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
}

// Form Sections
.form-section {
  margin-bottom: 32px;

  &:last-of-type {
    margin-bottom: 0;
  }
}

.section-label {
  display: block;
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 18px;
  font-weight: 600;
  color: #1e1e1e;
  margin-bottom: 8px;

  .required {
    color: #dc3545;
  }
}

.section-hint {
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 13px;
  color: #999;
  margin: 0 0 16px 0;
}

.form-label {
  display: block;
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 15px;
  font-weight: 500;
  color: #1e1e1e;
  margin-bottom: 8px;

  .required {
    color: #dc3545;
  }
}

.form-input,
.form-select,
.form-textarea {
  width: 100%;
  padding: 12px 16px;
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 15px;
  color: #1e1e1e;
  background: white;
  border: 1px solid #d0d0d0;
  border-radius: 8px;
  transition: all 0.3s;
  outline: none;

  &:focus {
    border-color: $primary;
    box-shadow: 0 0 0 3px rgba(111, 184, 165, 0.1);
  }

  &::placeholder {
    color: #999;
  }
}

.form-textarea {
  resize: vertical;
  min-height: 120px;
}

.char-count {
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 13px;
  color: #999;
  text-align: right;
  margin: 6px 0 0 0;
}

// Image Upload
.image-upload-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 16px;
}

.image-item {
  position: relative;
  aspect-ratio: 1;
  border-radius: 8px;
  overflow: hidden;

  .uploaded-image {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .remove-image-btn {
    position: absolute;
    top: 8px;
    right: 8px;
    width: 28px;
    height: 28px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(0, 0, 0, 0.5);
    border: none;
    border-radius: 50%;
    cursor: pointer;
    transition: all 0.3s;

    i {
      font-size: 20px;
      color: white;
    }

    &:hover {
      background: rgba(220, 53, 69, 0.9);
    }
  }

  .cover-badge {
    position: absolute;
    bottom: 8px;
    left: 8px;
    padding: 4px 10px;
    background: $primary;
    color: white;
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 12px;
    font-weight: 600;
    border-radius: 4px;
  }
}

.upload-placeholder {
  aspect-ratio: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 8px;
  background: #f9f9f9;
  border: 2px dashed #d0d0d0;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.3s;

  i {
    font-size: 32px;
    color: #999;
  }

  span {
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 14px;
    color: #999;
  }

  &:hover {
    background: #f0f0f0;
    border-color: $primary;

    i,
    span {
      color: $primary;
    }
  }
}

// Price Input
.price-input-wrapper {
  position: relative;
  display: flex;
  align-items: center;

  .currency-symbol {
    position: absolute;
    left: 16px;
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 15px;
    font-weight: 500;
    color: #666;
    pointer-events: none;
  }

  .price-input {
    padding-left: 48px;
  }
}

// Checkbox Group
.checkbox-group {
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
  margin-top: 12px;
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;

  .checkbox-input {
    width: 18px;
    height: 18px;
    cursor: pointer;
    accent-color: $primary;
  }

  .checkbox-text {
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 15px;
    color: #1e1e1e;
  }
}

// Condition Options
.condition-options {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}

.condition-option {
  flex: 1;
  min-width: 100px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 12px 20px;
  background: white;
  border: 2px solid #d0d0d0;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.3s;

  .condition-radio {
    display: none;
  }

  .condition-label {
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 15px;
    color: #666;
    font-weight: 500;
  }

  &:hover {
    border-color: $primary;
    background: #f9fffe;
  }

  &.active {
    border-color: $primary;
    background: $primary;

    .condition-label {
      color: white;
    }
  }
}

// Form Actions
.form-actions {
  display: flex;
  gap: 16px;
  justify-content: flex-end;
  margin-top: 40px;
  padding-top: 32px;
  border-top: 1px solid #e0e0e0;
}

.cancel-btn,
.publish-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 14px 32px;
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 16px;
  font-weight: 500;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.3s;
  min-width: 120px;
}

.cancel-btn {
  background: white;
  color: #666;
  border: 1px solid #d0d0d0;

  &:hover {
    background: #f5f5f5;
    border-color: #b0b0b0;
  }
}

.publish-btn {
  background: $primary;
  color: white;
  border: none;

  &:hover:not(:disabled) {
    background: #5fa795;
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(111, 184, 165, 0.3);
  }

  &:disabled {
    background: #b0d4cb;
    cursor: not-allowed;
  }

  .spin {
    animation: spin 1s linear infinite;
  }
}

@keyframes spin {
  from {
    transform: rotate(0deg);
  }
  to {
    transform: rotate(360deg);
  }
}

// Responsive
@media (max-width: 767.98px) {
  .main-content {
    padding: 20px 0 50px;
  }

  .create-container {
    padding: 0 15px;
  }

  .page-header {
    margin-bottom: 20px;

    .page-title {
      font-size: 24px;
    }
  }

  .form-card {
    padding: 30px 24px;
  }

  .image-upload-grid {
    grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
    gap: 12px;
  }

  .condition-options {
    flex-direction: column;
  }

  .condition-option {
    min-width: 100%;
  }

  .form-actions {
    flex-direction: column-reverse;
    gap: 12px;

    .cancel-btn,
    .publish-btn {
      width: 100%;
    }
  }
}

@media (max-width: 575.98px) {
  .main-content {
    padding: 15px 0 40px;
  }

  .create-container {
    padding: 0 10px;
  }

  .page-header {
    margin-bottom: 16px;

    .page-title {
      font-size: 20px;
    }

    .back-btn {
      width: 36px;
      height: 36px;

      i {
        font-size: 18px;
      }
    }

    .spacer {
      width: 36px;
    }
  }

  .form-card {
    padding: 24px 16px;
  }

  .section-label {
    font-size: 16px;
  }

  .form-label {
    font-size: 14px;
  }

  .image-upload-grid {
    grid-template-columns: repeat(2, 1fr);
    gap: 10px;
  }
}

// 【新增 2025-11-02】AI 自動填寫按鈕樣式
.ai-analyze-btn {
  margin-top: 16px;
  width: 100%;
  padding: 14px 24px;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  color: white;
  border: none;
  border-radius: 12px;
  font-size: 16px;
  font-weight: 600;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  transition: all 0.3s ease;
  box-shadow: 0 4px 12px rgba(102, 126, 234, 0.3);

  i {
    font-size: 20px;
  }

  &:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 6px 16px rgba(102, 126, 234, 0.4);
  }

  &:active:not(:disabled) {
    transform: translateY(0);
  }

  &:disabled {
    opacity: 0.6;
    cursor: not-allowed;
    background: linear-gradient(135deg, #999 0%, #666 100%);
  }
}

// 【新增 2025-11-02】AI 警告訊息樣式
.ai-warnings {
  margin-top: 16px;
  padding: 16px;
  background-color: #fff8e1;
  border-left: 4px solid #ffc107;
  border-radius: 8px;

  .warning-header {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 12px;
    font-weight: 600;
    color: #f57c00;

    i {
      font-size: 18px;
    }
  }

  .warning-list {
    margin: 0;
    padding-left: 24px;
    list-style-type: disc;

    li {
      margin-bottom: 6px;
      color: #e65100;
      font-size: 14px;
      line-height: 1.5;

      &:last-child {
        margin-bottom: 0;
      }
    }
  }
}
</style>
