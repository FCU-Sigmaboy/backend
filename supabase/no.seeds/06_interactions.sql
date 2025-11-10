-- =============================================
-- 模組三：互動功能
-- =============================================

-- Conversations 表
INSERT INTO public.conversations (id, item_id, buyer_id, seller_id, created_at, updated_at)
VALUES (1, 1, 'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', '488a4712-dd63-4938-9679-336f434ad263', '2023-10-27 10:15:00+00',
        '2023-10-27 10:16:00+00'),
       (2, 15, '9b900884-10cf-416c-bb5d-e577c4fbacba', '7140056b-c71c-489f-8f57-2eeb1694713e', '2023-10-27 10:17:00+00',
        '2023-10-27 10:18:00+00'),
       (3, 31, '7140056b-c71c-489f-8f57-2eeb1694713e', 'e773c5f7-172c-4976-a7be-d537a7e6e71e', '2023-10-27 10:19:00+00',
        '2023-10-27 10:20:00+00'),
       (4, 7, '488a4712-dd63-4938-9679-336f434ad263', 'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', '2023-10-27 10:21:00+00',
        '2023-10-27 10:22:00+00')
ON CONFLICT (id) DO NOTHING;

-- Conversation Messages 表
INSERT INTO public.conversation_messages (id, conversation_id, sender_id, content, is_read, sent_at)
VALUES (1, 1, 'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', '對襯衫有興趣,請問尺寸?', FALSE, '2023-10-27 10:15:15+00'),
       (2, 1, '488a4712-dd63-4938-9679-336f434ad263', 'M 號,詳細尺寸已更新', TRUE, '2023-10-27 10:16:00+00'),
       (3, 2, '9b900884-10cf-416c-bb5d-e577c4fbacba', 'Macbook 還有嗎?', FALSE, '2023-10-27 10:17:30+00'),
       (4, 3, '7140056b-c71c-489f-8f57-2eeb1694713e', '大衣的材質是什麼?', FALSE, '2023-10-27 10:19:45+00'),
       (5, 4, '488a4712-dd63-4938-9679-336f434ad263', '西裝褲全新嗎?', FALSE, '2023-10-27 10:21:15+00')
ON CONFLICT (id) DO NOTHING;

-- Following 表
INSERT INTO public.following (follower_id, following_id, created_at)
VALUES ('cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', '488a4712-dd63-4938-9679-336f434ad263', '2023-10-27 10:25:00+00'),
       ('7140056b-c71c-489f-8f57-2eeb1694713e', 'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', '2023-10-27 10:25:30+00'),
       ('9b900884-10cf-416c-bb5d-e577c4fbacba', '488a4712-dd63-4938-9679-336f434ad263', '2023-10-27 10:26:00+00'),
       ('e773c5f7-172c-4976-a7be-d537a7e6e71e', 'c8d6998b-79e3-4d56-a9ef-689eed9bd823', '2023-10-27 10:26:30+00')
ON CONFLICT (follower_id, following_id) DO NOTHING;

-- Favorites 表
INSERT INTO public.favorites (user_id, item_id, created_at)
VALUES ('cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', 6, '2023-10-27 10:27:00+00'),
       ('7140056b-c71c-489f-8f57-2eeb1694713e', 2, '2023-10-27 10:27:15+00'),
       ('9b900884-10cf-416c-bb5d-e577c4fbacba', 13, '2023-10-27 10:27:30+00'),
       ('c8d6998b-79e3-4d56-a9ef-689eed9bd823', 19, '2023-10-27 10:27:45+00'),
       ('e773c5f7-172c-4976-a7be-d537a7e6e71e', 24, '2023-10-27 10:28:00+00'),
       ('488a4712-dd63-4938-9679-336f434ad263', 31, '2023-10-27 10:28:15+00')
ON CONFLICT (user_id, item_id) DO NOTHING;

-- 重設序列值
SELECT setval('conversations_id_seq', (SELECT MAX(id) FROM public.conversations));
SELECT setval('conversation_messages_id_seq', (SELECT MAX(id) FROM public.conversation_messages));
