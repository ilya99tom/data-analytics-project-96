-- Размечаем платные/бесплатные сессии и создаем группы атрибуции
WITH sessions_with_groups AS (
    SELECT
        visitor_id,
        visit_date,
        source,
        medium,
        campaign,
        SUM(
            CASE
                WHEN
                    medium IN (
                        'cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social'
                    )
                    THEN 1
                ELSE 0
            END
        )
            OVER (
                PARTITION BY visitor_id
                ORDER BY visit_date
            )
            AS attribution_group
    FROM
        sessions
),

-- UTM-метки
attributed_sessions AS (
    SELECT
        visitor_id,
        visit_date,
        CASE
            WHEN
                attribution_group > 0
                THEN FIRST_VALUE(source) OVER (
                    PARTITION BY visitor_id, attribution_group
                    ORDER BY visit_date
                )
        END AS utm_source,
        CASE
            WHEN
                attribution_group > 0
                THEN FIRST_VALUE(medium) OVER (
                    PARTITION BY visitor_id, attribution_group
                    ORDER BY visit_date
                )
        END AS utm_medium,
        CASE
            WHEN
                attribution_group > 0
                THEN FIRST_VALUE(campaign) OVER (
                    PARTITION BY visitor_id, attribution_group
                    ORDER BY visit_date
                )
        END AS utm_campaign
    FROM
        sessions_with_groups
),

-- Последняя сессия для каждого лида
lead_to_session_map AS (
    SELECT
        l.lead_id,
        l.visitor_id,
        s.visit_date,
        ROW_NUMBER()
            OVER (
                PARTITION BY l.lead_id
                ORDER BY s.visit_date DESC
            )
            AS rn
    FROM
        leads AS l
    INNER JOIN
        sessions AS s
        ON l.visitor_id = s.visitor_id AND l.created_at >= s.visit_date
),

--Собираем финальную витрину
l AS (
    SELECT
        lsm.visit_date,
        lsm.visitor_id,
        l_main.lead_id,
        l_main.created_at,
        l_main.amount,
        l_main.closing_reason,
        l_main.status_id
    FROM
        lead_to_session_map AS lsm
    INNER JOIN
        leads AS l_main
        ON lsm.lead_id = l_main.lead_id
    WHERE
        lsm.rn = 1
)

--Собираем финальную витрину
SELECT
    s.visitor_id,
    s.visit_date,
    s.utm_source,
    s.utm_medium,
    s.utm_campaign,
    l.lead_id,
    l.created_at,
    l.amount,
    l.closing_reason,
    l.status_id
FROM
    attributed_sessions AS s
LEFT JOIN l
    ON s.visitor_id = l.visitor_id AND s.visit_date = l.visit_date
ORDER BY
    l.amount DESC NULLS LAST,
    s.visit_date ASC,
    s.utm_source ASC,
    s.utm_medium ASC,
    s.utm_campaign ASC
LIMIT 10;
