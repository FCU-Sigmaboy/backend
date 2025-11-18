-- 告訴 supabase_realtime：這張表只廣播括號內列出的欄位
-- 主要是將 'code' 欄位排除在外

ALTER PUBLICATION supabase_realtime
DROP TABLE public.transactions;

ALTER PUBLICATION supabase_realtime
    ADD TABLE public.transactions (id, item_id, giver_id, receiver_id, points_amount, carbon_amount_kg, transaction_status, completed_at, created_at, updated_at, giver_note, receiver_note);

-- 注意：這裡故意漏掉了 'code'