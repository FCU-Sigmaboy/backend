-- =============================================
-- 模組一:使用者管理 - Locations 表
-- =============================================

INSERT INTO public.locations (id, user_id, coordinates, type, is_primary, formatted_address, created_at, updated_at)
VALUES (1, '488a4712-dd63-4938-9679-336f434ad263', ST_GeogFromText('POINT(120.6400 24.1800)'), '家', TRUE,
        '台中市西屯區', '2023-10-27 10:00:30+00', '2023-10-27 10:00:30+00'),
       (2, 'cdf0fa87-4c7f-4a89-8ae6-7d2b8caaa788', ST_GeogFromText('POINT(120.6600 24.1500)'), '家', TRUE,
        '台中市南屯區', '2023-10-27 10:01:30+00', '2023-10-27 10:01:30+00'),
       (3, '7140056b-c71c-489f-8f57-2eeb1694713e', ST_GeogFromText('POINT(120.6800 24.1300)'), '家', TRUE, '台中市北區',
        '2023-10-27 10:02:30+00', '2023-10-27 10:02:30+00'),
       (4, '9b900884-10cf-416c-bb5d-e577c4fbacba', ST_GeogFromText('POINT(120.7000 24.1700)'), '家', TRUE, '台中市西區',
        '2023-10-27 10:03:30+00', '2023-10-27 10:03:30+00'),
       (5, 'c8d6998b-79e3-4d56-a9ef-689eed9bd823', ST_GeogFromText('POINT(120.6500 24.2000)'), '家', TRUE,
        '台中市豐原區', '2023-10-27 10:04:30+00', '2023-10-27 10:04:30+00'),
       (6, 'e773c5f7-172c-4976-a7be-d537a7e6e71e', ST_GeogFromText('POINT(120.6900 24.1600)'), '家', TRUE, '台中市東區',
        '2023-10-27 10:05:30+00', '2023-10-27 10:05:30+00')
ON CONFLICT (id) DO NOTHING;

-- 重設序列值
SELECT setval('locations_id_seq', (SELECT MAX(id) FROM public.locations));
