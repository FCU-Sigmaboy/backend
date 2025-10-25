-- supabase/migrations/[timestamp]_setup_storage_rls.sql

-- =============================================
-- Avatars Bucket RLS 政策
-- =============================================

-- 1. 允許所有人讀取頭像(因為是公開 bucket)
CREATE POLICY "Public avatars are accessible to everyone"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'avatars');

-- 2. 允許認證使用者上傳自己的頭像
CREATE POLICY "Users can upload their own avatar"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
    bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- 3. 允許使用者更新自己的頭像
CREATE POLICY "Users can update their own avatar"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
    bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- 4. 允許使用者刪除自己的頭像
CREATE POLICY "Users can delete their own avatar"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
    bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- =============================================
-- Items Bucket RLS 政策
-- =============================================

-- 1. 允許所有人讀取物品圖片
CREATE POLICY "Public item images are accessible to everyone"
    ON storage.objects FOR SELECT
    TO public
    USING (bucket_id = 'items');

-- 2. 允許認證使用者上傳物品圖片到自己的資料夾
CREATE POLICY "Users can upload their own item images"
    ON storage.objects FOR INSERT
    TO authenticated
    WITH CHECK (
    bucket_id = 'items'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- 3. 允許物品擁有者更新圖片
CREATE POLICY "Item owners can update their images"
    ON storage.objects FOR UPDATE
    TO authenticated
    USING (
    bucket_id = 'items'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- 4. 允許物品擁有者刪除圖片
CREATE POLICY "Item owners can delete their images"
    ON storage.objects FOR DELETE
    TO authenticated
    USING (
    bucket_id = 'items'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );
