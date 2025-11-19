<template>
  <div class="create-listing-page">
    <AppHeader :user-points="userPoints" />

    <main class="main-content">
      <!-- Breadcrumb -->
      <Breadcrumb :items="breadcrumbItems" />

      <div class="create-container">
        <!-- Page Header -->
        <div class="page-header">
          <button class="back-btn" @click="goBack">
            <i class="bi bi-arrow-left"></i>
          </button>
          <h1 class="page-title">{{ isEdit ? '編輯刊登' : '刊登物品' }}</h1>
          <div class="spacer"></div>
        </div>

        <!-- Loading State - Skeleton -->
        <div v-if="isLoading" class="form-card skeleton-loading">
          <!-- Skeleton Header -->
          <div class="skeleton-section">
            <div class="skeleton-label"></div>
            <div class="skeleton-hint"></div>
            <div class="skeleton-image-grid">
              <div v-for="i in 4" :key="`skeleton-img-${i}`" class="skeleton-image-box"></div>
            </div>
          </div>

          <!-- Skeleton Input Fields -->
          <div class="skeleton-section">
            <div class="skeleton-label"></div>
            <div class="skeleton-input"></div>
          </div>

          <div class="skeleton-section">
            <div class="skeleton-label"></div>
            <div class="skeleton-select"></div>
          </div>

          <div class="skeleton-section">
            <div class="skeleton-label"></div>
            <div class="skeleton-textarea"></div>
          </div>

          <div class="skeleton-section">
            <div class="skeleton-label"></div>
            <div class="skeleton-input short"></div>
          </div>

          <div class="skeleton-section">
            <div class="skeleton-label"></div>
            <div class="skeleton-options">
              <div v-for="i in 5" :key="`skeleton-opt-${i}`" class="skeleton-option"></div>
            </div>
          </div>

          <div class="skeleton-section">
            <div class="skeleton-label"></div>
            <div class="skeleton-select"></div>
          </div>

          <!-- Skeleton Actions -->
          <div class="skeleton-actions">
            <div class="skeleton-button"></div>
            <div class="skeleton-button primary"></div>
          </div>
        </div>

        <!-- Create Form -->
        <div v-else class="form-card">
          <form @submit.prevent="handleSubmit">
            <!-- Image Upload Section -->
            <div class="form-section">
              <label class="section-label">
                商品照片 <span class="required">*</span>
              </label>
              <p class="section-hint">最多上傳 8 張照片，第一張為封面照片。支援拖曳上傳</p>

              <div
                class="image-upload-dropzone"
                :class="{ 'is-dragging': isDragging }"
                @dragover.prevent="handleDragOver"
                @dragleave.prevent="handleDragLeave"
                @drop.prevent="handleDrop"
              >
                <div class="image-upload-grid">
                  <!-- Uploaded Images -->
                  <div
                    v-for="(image, index) in formData.images"
                    :key="index"
                    class="image-item"
                    :class="{ 
                      'is-cover': index === 0,
                      'is-dragging': draggedImageIndex === index,
                      'drag-over': dragOverImageIndex === index
                    }"
                    draggable="true"
                    @dragstart="handleImageDragStart(index, $event)"
                    @dragover="handleImageDragOver(index, $event)"
                    @dragenter="handleImageDragEnter(index, $event)"
                    @drop="handleImageDrop(index, $event)"
                    @dragend="handleImageDragEnd"
                    @click="openImageEditor(index)"
                  >
                    <img :src="image" alt="Product Image" class="uploaded-image" />
                    <button
                      type="button"
                      class="remove-image-btn"
                      @click.stop="removeImage(index)"
                    >
                      <i class="bi bi-x-circle-fill"></i>
                    </button>
                    <span v-if="index === 0" class="cover-badge">封面</span>
                    <button
                      type="button"
                      class="edit-image-btn"
                      @click.stop="openImageEditor(index)"
                    >
                      <i class="bi bi-pencil-square" aria-hidden="true"></i>
                      <span class="visually-hidden">
                        調整第 {{ index + 1 }} 張照片
                      </span>
                    </button>
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

                <!-- Drag Overlay -->
                <div v-if="isDragging" class="drag-overlay">
                  <i class="bi bi-cloud-upload"></i>
                  <p>拖曳圖片到這裡上傳</p>
                </div>
              </div>

              <input
                ref="imageInput"
                type="file"
                accept="image/*"
                multiple
                style="display: none"
                @change="handleImageUpload"
              />
            </div>

            <!-- AI Recognition Button -->
            <div v-if="formData.images.length > 0 && !isEdit" class="form-section ai-section">
              <button
                type="button"
                class="ai-analyze-btn"
                :disabled="isAnalyzing"
                @click="handleAIAnalyze"
              >
                <i v-if="!isAnalyzing" class="bi bi-stars"></i>
                <i v-else class="bi bi-arrow-repeat spin"></i>
                <span v-if="!isAnalyzing">使用 AI 辨識物品資訊</span>
                <span v-else>AI 辨識中...</span>
              </button>
              <p class="ai-hint">
                <i class="bi bi-info-circle"></i>
                AI 會根據第一張照片自動填入商品資訊，您可以再自行調整
              </p>
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
                <option value="">請選擇分類</option>
                <option
                  v-for="subCat in subCategories"
                  :key="subCat.id"
                  :value="subCat.id"
                >
                  {{ subCat.name }}
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
                點數 <span class="required">*</span>
              </label>
              <div class="price-input-wrapper">
                <span class="currency-symbol">點數</span>
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
              <label class="form-label">
                交易地點 <span class="required">*</span>
              </label>
              <div class="location-options">
                <label
                  :class="['location-option', { 
                    active: formData.usePrimaryLocation === true,
                    disabled: !userLocations.primary 
                  }]"
                >
                  <input
                    v-model="formData.usePrimaryLocation"
                    type="radio"
                    :value="true"
                    class="location-radio"
                    :disabled="!userLocations.primary"
                    required
                  />
                  <div class="location-content">
                    <span class="location-label">
                      <i class="bi bi-geo-alt-fill"></i>
                      使用主要地點
                    </span>
                    <span v-if="userLocations.primary" class="location-address">
                      {{ userLocations.primary.formatted_address }}
                    </span>
                    <span v-else class="location-not-set">
                      <i class="bi bi-exclamation-circle"></i>
                      未設定
                    </span>
                  </div>
                </label>
                <label
                  :class="['location-option', { 
                    active: formData.usePrimaryLocation === false,
                    disabled: !userLocations.secondary 
                  }]"
                >
                  <input
                    v-model="formData.usePrimaryLocation"
                    type="radio"
                    :value="false"
                    class="location-radio"
                    :disabled="!userLocations.secondary"
                    required
                  />
                  <div class="location-content">
                    <span class="location-label">
                      <i class="bi bi-geo-alt"></i>
                      使用次要地點
                    </span>
                    <span v-if="userLocations.secondary" class="location-address">
                      {{ userLocations.secondary.formatted_address }}
                    </span>
                    <span v-else class="location-not-set">
                      <i class="bi bi-exclamation-circle"></i>
                      未設定
                    </span>
                  </div>
                </label>
              </div>
              <p class="form-hint">
                請先在個人資料中設定主要地點或次要地點。
                <router-link :to="{ name: 'UserProfile' }" class="link-text">
                  前往個人資料設定
                </router-link>
              </p>
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

    <ImageCropper
      v-model:show="showImageCropper"
      :image-src="cropperImageSrc"
      title="調整商品照片"
      :aspect-ratio-locked="false"
      @confirm="handleImageEditConfirm"
      @cancel="handleImageEditCancel"
    />
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { supabase } from '@/lib/supabase';
import { getItemById } from '../api/get_itemByIdAPI';
import { updateMyItem } from '../api/update_myItemAPI';
import { compressImage, uploadItemImage } from '../api/upload_imageAPI';
import { analyzeItemImage } from '../api/analyze_itemImageAPI';
import AppHeader from '../components/AppHeader.vue';
import AppFooter from '../components/AppFooter.vue';
import Breadcrumb from '../components/Breadcrumb.vue';
import ImageCropper from '../components/ImageCropper.vue';

const route = useRoute();
const router = useRouter();

// State
const userPoints = ref(500);
const itemId = computed(() => route.params.id ? Number(route.params.id) : null);
const isEdit = computed(() => !!itemId.value);

// Breadcrumb items
const breadcrumbItems = computed(() => {
  if (isEdit.value) {
    return [
      { label: '我的刊登', to: { name: 'ManageListings' } },
      { label: '編輯刊登' }
    ];
  }
  return [{ label: '刊登物品' }];
});
const isSubmitting = ref(false);
const isLoading = ref(!!route.params.id); // 如果是編輯模式，初始為 true
const isDragging = ref(false);
const imageInput = ref(null);
const subCategories = ref([]);
const showImageCropper = ref(false);
const cropperImageSrc = ref('');
const editingImageIndex = ref(null);
const userLocations = ref({
  primary: null,
  secondary: null
});
const isAnalyzing = ref(false); // AI 辨識中

// 拖曳排序相關
const draggedImageIndex = ref(null);
const dragOverImageIndex = ref(null);

const formData = ref({
  images: [],        // 預覽用的 base64 URLs
  imageFiles: [],    // 實際的 File 物件
  title: '',
  category: '',
  description: '',
  price: 0,
  condition: '',
  usePrimaryLocation: true // 預設使用主要地點
});

const conditions = [
  { value: '全新', label: '全新' },
  { value: '近全新', label: '近全新' },
  { value: '良好', label: '良好' },
  { value: '普通', label: '普通' },
  { value: '需修理', label: '需修理' }
];

// Fetch categories from database
const fetchCategories = async () => {
  try {
    console.log('🔍 Fetching sub_categories from database...');

    const { data, error } = await supabase
      .from('sub_categories')
      .select('id, name')
      .order('id');

    if (error) {
      console.error('❌ Error fetching sub_categories:', error);
      return;
    }

    subCategories.value = data || [];
    console.log('✅ Loaded sub_categories:', subCategories.value);
  } catch (error) {
    console.error('❌ Failed to fetch categories:', error);
  }
};

// Fetch user's locations from database
const fetchUserLocations = async () => {
  try {
    console.log('📍 Fetching user locations...');

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      console.error('❌ User not authenticated');
      return;
    }

    const { data, error } = await supabase
      .from('locations')
      .select('id, formatted_address, type, is_primary')
      .eq('user_id', user.id);

    if (error) {
      console.error('❌ Error fetching locations:', error);
      return;
    }

    // Separate primary and secondary locations
    if (data && data.length > 0) {
      userLocations.value.primary = data.find(loc => loc.is_primary === true) || null;
      userLocations.value.secondary = data.find(loc => loc.is_primary === false) || null;
    }

    console.log('Loaded user locations:', userLocations.value);
  } catch (error) {
    console.error('Failed to fetch user locations:', error);
  }
};

// Load item data for editing
const loadItemData = async () => {
  if (!itemId.value) return;

  try {
    isLoading.value = true;
    console.log('📝 Loading item data for editing...');

    const item = await getItemById(itemId.value);

    if (!item) {
      alert('找不到該物品');
      router.push({ name: 'ManageListings' });
      return;
    }

    // Populate form with item data
    const imageUrls = item.image_urls || [];
    formData.value = {
      images: imageUrls,
      imageFiles: imageUrls.map(() => null), // 為每個現有圖片佔位 null
      title: item.title || '',
      category: item.sub_category_id || '',
      description: item.description || '',
      price: item.price || 0,
      condition: item.condition || '',
      usePrimaryLocation: item.use_primary_location !== undefined ? item.use_primary_location : true
    };

    // 驗證編輯的物品所使用的地點是否仍然存在
    const selectedLocation = item.use_primary_location 
      ? userLocations.value.primary 
      : userLocations.value.secondary;

    if (!selectedLocation) {
      const locationType = item.use_primary_location ? '主要地點' : '次要地點';
      console.warn(`⚠️ 此物品原本使用${locationType},但該地點已不存在`);
      alert(`注意：此物品原本使用${locationType},但您目前尚未設定該地點。請重新選擇交易地點。`);
    }

    console.log('✅ Item data loaded:', formData.value);
  } catch (error) {
    console.error('❌ Failed to load item:', error);
    alert(`載入失敗：${error.message}`);
    router.push({ name: 'ManageListings' });
  } finally {
    isLoading.value = false;
  }
};

// Load categories and item data on mount
onMounted(async () => {
  await fetchCategories();
  await fetchUserLocations();

  if (isEdit.value) {
    await loadItemData();
  }
});

// Methods
const goBack = () => {
  router.back();
};

const triggerImageInput = () => {
  imageInput.value.click();
};

const handleImageUpload = async (event) => {
  const files = Array.from(event.target.files);
  const remainingSlots = 8 - formData.value.images.length;
  const filesToProcess = files.slice(0, remainingSlots);

  for (const file of filesToProcess) {
    // Compress image first
    const compressedFile = await compressImage(file);

    // Save File object for upload
    formData.value.imageFiles.push(compressedFile);

    // Convert to base64 for preview
    const reader = new FileReader();
    reader.onload = (e) => {
      formData.value.images.push(e.target.result);
    };
    reader.readAsDataURL(compressedFile);
  }

  // Clear input
  event.target.value = '';
};

const removeImage = (index) => {
  formData.value.images.splice(index, 1);
  formData.value.imageFiles.splice(index, 1);
};

const openImageEditor = (index) => {
  const targetImage = formData.value.images[index];
  if (!targetImage) return;
  editingImageIndex.value = index;
  cropperImageSrc.value = targetImage;
  showImageCropper.value = true;
};

const handleImageEditConfirm = async (blob) => {
  if (editingImageIndex.value === null) return;

  const index = editingImageIndex.value;
  const editedFile = new File([blob], `listing-image-${index + 1}.webp`, { type: 'image/webp' });
  
  // Compress the cropped image
  const compressedFile = await compressImage(editedFile);
  formData.value.imageFiles[index] = compressedFile;

  const reader = new FileReader();
  reader.onload = (e) => {
    formData.value.images.splice(index, 1, e.target.result);
  };
  reader.readAsDataURL(compressedFile);

  showImageCropper.value = false;
  cropperImageSrc.value = '';
  editingImageIndex.value = null;
};

const handleImageEditCancel = () => {
  showImageCropper.value = false;
  cropperImageSrc.value = '';
  editingImageIndex.value = null;
};

// Drag and Drop handlers
const handleDragOver = (event) => {
  // 只在外部拖曳檔案時顯示上傳提示
  if (draggedImageIndex.value === null) {
    isDragging.value = true;
  }
};

const handleDragLeave = (event) => {
  // Only set to false if leaving the dropzone entirely
  if (event.target.classList.contains('image-upload-dropzone') && draggedImageIndex.value === null) {
    isDragging.value = false;
  }
};

const handleDrop = async (event) => {
  isDragging.value = false;

  const files = Array.from(event.dataTransfer.files);

  // Filter only image files
  const imageFiles = files.filter(file => file.type.startsWith('image/'));

  if (imageFiles.length === 0) {
    return; // 靜默失敗,可能是內部拖曳
  }

  const remainingSlots = 8 - formData.value.images.length;
  const filesToProcess = imageFiles.slice(0, remainingSlots);

  if (imageFiles.length > remainingSlots) {
    alert(`最多只能上傳 8 張照片，已自動選取前 ${remainingSlots} 張`);
  }

  for (const file of filesToProcess) {
    // Compress image first
    const compressedFile = await compressImage(file);

    // Save File object for upload
    formData.value.imageFiles.push(compressedFile);

    // Convert to base64 for preview
    const reader = new FileReader();
    reader.onload = (e) => {
      formData.value.images.push(e.target.result);
    };
    reader.readAsDataURL(compressedFile);
  }
};

// 圖片拖曳排序處理
const handleImageDragStart = (index, event) => {
  // 檢查是否真的是從這個圖片開始拖曳(內部排序)
  if (event.target.closest('.image-item')) {
    event.stopPropagation();
    draggedImageIndex.value = index;
    event.dataTransfer.effectAllowed = 'move';
    event.dataTransfer.setData('text/plain', index.toString());
  }
};

const handleImageDragOver = (index, event) => {
  event.preventDefault();
  event.stopPropagation();
  event.dataTransfer.dropEffect = 'move';
  dragOverImageIndex.value = index;
};

const handleImageDragEnter = (index, event) => {
  event.stopPropagation();
  dragOverImageIndex.value = index;
};

const handleImageDragLeave = () => {
  // 可選：延遲清除以避免閃爍
};

const handleImageDrop = (targetIndex, event) => {
  event.preventDefault();
  event.stopPropagation();
  
  const sourceIndex = draggedImageIndex.value;
  
  // 檢查是否為內部拖曳排序
  if (sourceIndex !== null) {
    // 這是內部圖片排序
    if (sourceIndex !== targetIndex) {
      // 重新排列圖片陣列
      const newImages = [...formData.value.images];
      const newImageFiles = [...formData.value.imageFiles];
      
      const [movedImage] = newImages.splice(sourceIndex, 1);
      const [movedFile] = newImageFiles.splice(sourceIndex, 1);
      
      newImages.splice(targetIndex, 0, movedImage);
      newImageFiles.splice(targetIndex, 0, movedFile);
      
      formData.value.images = newImages;
      formData.value.imageFiles = newImageFiles;
    }
    
    draggedImageIndex.value = null;
    dragOverImageIndex.value = null;
    return; // 內部排序完成，不再繼續處理
  }
  
  // 這是外部檔案拖曳到內部圖片上
  const files = event.dataTransfer.files;
  if (files && files.length > 0) {
    handleDrop(event);
  }
};

const handleImageDragEnd = () => {
  draggedImageIndex.value = null;
  dragOverImageIndex.value = null;
};

// AI 辨識功能
const handleAIAnalyze = async () => {
  if (formData.value.images.length === 0) {
    alert('請先上傳至少一張照片');
    return;
  }

  isAnalyzing.value = true;

  try {
    console.log('🤖 開始 AI 辨識...');

    // 1. 先上傳第一張圖片到 Storage（用於 AI 分析）
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      throw new Error('使用者未登入');
    }

    // 產生臨時 ID 用於圖片路徑
    const tempItemId = `temp-ai-${Date.now()}`;
    const firstImageFile = formData.value.imageFiles[0];

    if (!firstImageFile) {
      throw new Error('無法取得圖片檔案');
    }

    console.log('📤 上傳圖片到 Storage...');
    // 上傳第一張圖片（檔案已經壓縮過，傳入 false 避免重複壓縮）
    const imageUrl = await uploadItemImage(firstImageFile, user.id, tempItemId, false);
    console.log('✅ 圖片已上傳:', imageUrl);

    // 2. 呼叫 AI 分析 API
    console.log('🤖 呼叫 AI 分析...');
    const result = await analyzeItemImage(imageUrl);

    // 3. 填入表單資料
    if (result.title) {
      formData.value.title = result.title;
    }
    if (result.description) {
      formData.value.description = result.description;
    }
    if (result.sub_category_id) {
      formData.value.category = result.sub_category_id;
    }
    if (result.condition) {
      formData.value.condition = result.condition;
    }

    // 4. 顯示警告訊息（如果有）
    if (result.warnings && result.warnings.length > 0) {
      console.warn('⚠️ AI 警告:', result.warnings);
      alert('AI 辨識提醒：\n' + result.warnings.join('\n'));
    }

    console.log('✅ AI 辨識完成，信心度:', result.confidence);
    alert(`AI 辨識成功！\n信心度: ${(result.confidence * 100).toFixed(0)}%\n\n請檢查並調整自動填入的資訊。`);

  } catch (error) {
    console.error('❌ AI 辨識失敗:', error);
    alert(`AI 辨識失敗：${error.message}\n\n請手動填寫物品資訊。`);
  } finally {
    isAnalyzing.value = false;
  }
};

const handleSubmit = async () => {
  // Validate images
  if (formData.value.images.length === 0) {
    alert('請至少上傳一張商品照片');
    return;
  }

  // Validate location exists
  const selectedLocation = formData.value.usePrimaryLocation 
    ? userLocations.value.primary 
    : userLocations.value.secondary;

  if (!selectedLocation) {
    const locationType = formData.value.usePrimaryLocation ? '主要地點' : '次要地點';
    alert(`請先在個人資料中設定${locationType}後再刊登物品`);
    return;
  }

  isSubmitting.value = true;

  try {
    if (isEdit.value) {
      // Update existing item
      console.log('📝 Updating item:', formData.value);

      // 檢查哪些圖片需要上傳 (有對應的 File 物件)
      const finalImageUrls = [];
      const { data: { user } } = await supabase.auth.getUser();
      const { uploadItemImage } = await import('../api/upload_imageAPI');
      
      for (let i = 0; i < formData.value.images.length; i++) {
        const imagePreview = formData.value.images[i];
        const imageFile = formData.value.imageFiles[i];
        
        // 如果有對應的 Blob/File 物件 (不是 null)，需要上傳
        if (imageFile instanceof Blob) {
          // 如果是 Blob 但不是 File，轉換為 File
          const fileToUpload = imageFile instanceof File 
            ? imageFile 
            : new File([imageFile], `image-${i}.webp`, { type: imageFile.type });
          // 傳入 false 因為檔案已經壓縮過
          const uploadedUrl = await uploadItemImage(fileToUpload, user.id, itemId.value, false);
          finalImageUrls.push(uploadedUrl);
        } 
        // 否則使用原有的 URL
        else if (imagePreview.startsWith('http')) {
          finalImageUrls.push(imagePreview);
        }
      }

      const updateData = {
        title: formData.value.title,
        description: formData.value.description,
        condition: formData.value.condition,
        price: formData.value.price,
        sub_category_id: formData.value.category,
        image_urls: finalImageUrls,
        use_primary_location: formData.value.usePrimaryLocation
      };

      const result = await updateMyItem(itemId.value, updateData);

      console.log('✅ Item updated successfully:', result);
    } else {
      // Create new item
      console.log('📝 Creating new listing:', formData.value);

      const itemData = {
        sub_category_id: formData.value.category,
        use_primary_location: formData.value.usePrimaryLocation,
        title: formData.value.title,
        description: formData.value.description,
        condition: formData.value.condition,
        price: formData.value.price,
        tags: []
      };

      // Use createItemWithImages to upload images and create item
      // 傳入 true 表示檔案已經在前端壓縮過，避免重複壓縮
      const { createItemWithImages } = await import('../api/create_myItemAPI');
      const result = await createItemWithImages(itemData, formData.value.imageFiles, true);

      console.log('✅ Listing created successfully:', result);
    }

    // Navigate to manage listings page
    router.push({ name: 'ManageListings' });
  } catch (error) {
    console.error('❌ Error submitting listing:', error);
    alert((isEdit.value ? '更新' : '刊登') + '失敗：' + error.message);
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
  padding-bottom: 60px;
}

.create-container {
  max-width: 900px;
  margin: 0 auto;
  padding: 0 20px;
}

// Skeleton Loading
.skeleton-loading {
  padding: 40px;

  .skeleton-section {
    margin-bottom: 32px;

    &:last-of-type {
      margin-bottom: 0;
    }
  }

  .skeleton-label {
    width: 120px;
    height: 20px;
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    border-radius: 4px;
    margin-bottom: 12px;
    animation: shimmer 1.5s ease-in-out infinite;
  }

  .skeleton-hint {
    width: 250px;
    height: 14px;
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    border-radius: 4px;
    margin-bottom: 16px;
    animation: shimmer 1.5s ease-in-out infinite;
  }

  .skeleton-image-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
  }

  .skeleton-image-box {
    aspect-ratio: 1;
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    border-radius: 8px;
    animation: shimmer 1.5s ease-in-out infinite;
  }

  .skeleton-input {
    width: 100%;
    height: 48px;
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    border-radius: 8px;
    animation: shimmer 1.5s ease-in-out infinite;

    &.short {
      width: 40%;
    }
  }

  .skeleton-select {
    width: 100%;
    height: 48px;
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    border-radius: 8px;
    animation: shimmer 1.5s ease-in-out infinite;
  }

  .skeleton-textarea {
    width: 100%;
    height: 140px;
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    border-radius: 8px;
    animation: shimmer 1.5s ease-in-out infinite;
  }

  .skeleton-options {
    display: flex;
    flex-wrap: wrap;
    gap: 12px;
  }

  .skeleton-option {
    flex: 1;
    min-width: 100px;
    height: 48px;
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    border-radius: 8px;
    animation: shimmer 1.5s ease-in-out infinite;
  }

  .skeleton-actions {
    display: flex;
    gap: 16px;
    justify-content: flex-end;
    margin-top: 40px;
    padding-top: 32px;
    border-top: 1px solid #e0e0e0;
  }

  .skeleton-button {
    width: 120px;
    height: 50px;
    background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
    background-size: 200% 100%;
    border-radius: 8px;
    animation: shimmer 1.5s ease-in-out infinite;

    &.primary {
      opacity: 0.8;
    }
  }
}

@keyframes shimmer {
  0% {
    background-position: 200% 0;
  }
  100% {
    background-position: -200% 0;
  }
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

// AI Section
.ai-section {
  background: linear-gradient(135deg, #f5f8ff 0%, #e8f4f8 100%);
  padding: 24px;
  border-radius: 12px;
  border: 2px dashed #6fb8a5;
  text-align: center;
}

.ai-analyze-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 16px 32px;
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 16px;
  font-weight: 600;
  color: white;
  background: linear-gradient(135deg, #6fb8a5 0%, #5fa795 100%);
  border: none;
  border-radius: 10px;
  cursor: pointer;
  transition: all 0.3s;
  box-shadow: 0 4px 12px rgba(111, 184, 165, 0.3);

  i {
    font-size: 20px;
  }

  &:hover:not(:disabled) {
    background: linear-gradient(135deg, #5fa795 0%, #4f9785 100%);
    transform: translateY(-2px);
    box-shadow: 0 6px 16px rgba(111, 184, 165, 0.4);
  }

  &:disabled {
    background: #b0d4cb;
    cursor: not-allowed;
    transform: none;
    box-shadow: none;
  }

  .spin {
    animation: spin 1s linear infinite;
  }
}

.ai-hint {
  margin-top: 12px;
  margin-bottom: 0;
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 13px;
  color: #5a7c91;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;

  i {
    font-size: 14px;
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

.form-hint {
  font-family: 'Noto Sans TC', sans-serif;
  font-size: 13px;
  color: #666;
  margin: 8px 0 0 0;

  .link-text {
    color: $primary;
    text-decoration: none;
    font-weight: 500;

    &:hover {
      text-decoration: underline;
    }
  }
}

// Image Upload
.image-upload-dropzone {
  position: relative;
  padding: 16px;
  border: 2px dashed #d0d0d0;
  border-radius: 12px;
  background: #fafafa;
  transition: all 0.3s;

  &.is-dragging {
    border-color: $primary;
    background: rgba(111, 184, 165, 0.05);
  }
}

.image-upload-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: 16px;
  transition: all 0.3s ease;
}

.drag-overlay {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background: rgba(111, 184, 165, 0.95);
  border-radius: 12px;
  color: white;
  pointer-events: none;
  z-index: 10;

  i {
    font-size: 64px;
    margin-bottom: 16px;
  }

  p {
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 18px;
    font-weight: 600;
    margin: 0;
  }
}

.image-item {
  position: relative;
  aspect-ratio: 1;
  border-radius: 8px;
  overflow: hidden;
  cursor: move;
  border: 1px solid transparent;
  transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);

  &:focus-visible {
    outline: none;
    border-color: rgba(4, 112, 97, 0.6);
    box-shadow: 0 0 0 2px rgba(4, 112, 97, 0.2);
  }

  &:hover .uploaded-image,
  &:focus-within .uploaded-image {
    filter: brightness(0.95);
  }

  &.is-dragging {
    opacity: 0.4;
    transform: scale(0.92) rotate(2deg);
    z-index: 1000;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.2);
  }

  &.drag-over {
    border-color: $primary;
    background: rgba(111, 184, 165, 0.08);
    box-shadow: 0 0 0 3px rgba(111, 184, 165, 0.2);
    transform: scale(1.08);
    
    &::before {
      content: '';
      position: absolute;
      inset: 0;
      background: rgba(111, 184, 165, 0.1);
      border-radius: 8px;
      z-index: 1;
      animation: pulse-drag 0.8s ease-in-out infinite;
    }
  }

  .uploaded-image {
    width: 100%;
    height: 100%;
    object-fit: contain;
    background: #f5f8f7;
    transition: filter 0.2s ease;
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

  .edit-image-btn {
    position: absolute;
    bottom: 8px;
    right: 8px;
    width: 32px;
    height: 32px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    border: none;
    background: rgba(30, 30, 30, 0.65);
    color: #fff;
    cursor: pointer;
    transition: background 0.2s, transform 0.2s, opacity 0.2s;
    opacity: 0;
    pointer-events: none;

    &:hover {
      background: rgba(4, 112, 97, 0.8);
      transform: scale(1.05);
    }

    i {
      font-size: 16px;
    }
  }

  &:hover .edit-image-btn,
  &:focus-within .edit-image-btn {
    opacity: 1;
    pointer-events: auto;
  }
}

@media (hover: none) {
  .image-item {
    cursor: pointer;

    .edit-image-btn {
      opacity: 1;
      pointer-events: auto;
    }
  }
}

.visually-hidden {
  position: absolute !important;
  width: 1px;
  height: 1px;
  padding: 0;
  margin: -1px;
  overflow: hidden;
  clip: rect(0, 0, 0, 0);
  white-space: nowrap;
  border: 0;
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
    padding-left: 64px;
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

// Location Options
.location-options {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
}

.location-option {
  flex: 1;
  min-width: 200px;
  display: flex;
  align-items: flex-start;
  padding: 16px 20px;
  background: white;
  border: 2px solid #d0d0d0;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.3s;

  .location-radio {
    display: none;
  }

  .location-content {
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .location-label {
    display: flex;
    align-items: center;
    gap: 8px;
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 15px;
    color: #666;
    font-weight: 600;

    i {
      font-size: 18px;
    }
  }

  .location-address {
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 13px;
    color: #888;
    line-height: 1.5;
    padding-left: 26px;
  }

  .location-not-set {
    display: flex;
    align-items: center;
    gap: 6px;
    font-family: 'Noto Sans TC', sans-serif;
    font-size: 13px;
    color: #dc3545;
    padding-left: 26px;

    i {
      font-size: 14px;
    }
  }

  &:hover:not(.disabled) {
    border-color: $primary;
    background: #f9fffe;
  }

  &.active {
    border-color: $primary;
    background: $primary;

    .location-label {
      color: white;
    }

    .location-address {
      color: rgba(255, 255, 255, 0.9);
    }
  }

  &.disabled {
    opacity: 0.5;
    cursor: not-allowed;
    background: #f5f5f5;
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

@keyframes pulse-drag {
  0%, 100% {
    opacity: 0.6;
  }
  50% {
    opacity: 1;
  }
}

// Responsive
@media (max-width: 767.98px) {
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

  .skeleton-loading {
    padding: 30px 24px;

    .skeleton-image-grid {
      grid-template-columns: repeat(3, 1fr);
      gap: 12px;
    }

    .skeleton-actions {
      flex-direction: column-reverse;
      gap: 12px;

      .skeleton-button {
        width: 100%;
      }
    }
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

  .location-options {
    flex-direction: column;
  }

  .location-option {
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

  .skeleton-loading {
    padding: 24px 16px;

    .skeleton-image-grid {
      grid-template-columns: repeat(2, 1fr);
      gap: 10px;
    }

    .skeleton-options {
      flex-direction: column;
    }

    .skeleton-option {
      min-width: 100%;
    }
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
</style>
