-- =============================================
-- 模組一：使用者管理 - Users 表
-- =============================================

INSERT INTO public.users (id, nickname, profile_picture_url, avg_rating, created_at, updated_at)
VALUES ('488a4712-dd63-4938-9679-336f434ad263', 'Tao', 'https://example.com/tao_profile.jpg', 4.5,
        now(), now()),
       ('cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', 'Yo', 'https://example.com/yo_profile.jpg', 4.8,
        now(), now()),
       ('7140056b-c71c-489f-8f57-2eeb1694713e', 'Lee', 'https://example.com/lee_profile.jpg',
        4.2, now(), now()),
       ('9b900884-10cf-416c-bb5d-e577c4fbacba', 'Lin', 'https://example.com/lin_profile.jpg',
        4.7, now(), now()),
       ('c8d6998b-79e3-4d56-a9ef-689eed9bd823', 'Liao', 'https://example.com/liao_profile.jpg',
        4.0, now(), now()),
       ('e773c5f7-172c-4976-a7be-d537a7e6e71e', 'Chen',
        'https://example.com/chen_profile.jpg', 4.6, now(), now())
ON CONFLICT (id) DO NOTHING;
