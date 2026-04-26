--1.CPM (Стоимость за тысячу показов) = 168.28
--Формула: `(Общие рекламные затраты / Общие показы) × 1000`
--Бизнес-влияние: Измеряет эффективность затрат на кампании по повышению узнаваемости бренда.
select round(sum(spent)/sum(impressions)*1000, 2) as CRM 
from campaigns

--2.CPC (Стоимость за клик) = 5.82
--Формула: `Общие рекламные затраты / Общие клики`
--Бизнес-влияние: Измеряет эффективность затрат на привлечение трафика. Критически важно для оптимизации performance-маркетинга.
select round(sum(spent)/sum(clicks), 2) as CPC --стоимость за 1 клик
from campaigns

--3.CTR (Коэффициент кликабельности) = 3.00
--Формула: `(Общие клики / Общие показы)`
--Бизнес-влияние: Измеряет релевантность рекламы и эффективность креативов. Высокий CTR указывает на лучшее таргетирование и сообщения.
select round(sum(clicks) * 1.0/sum(impressions), 2) * 100 as CTR 
from campaigns

--4.CAC (Стоимость привлечения клиента) = 56342.00 общие????
--Формула:`Затраты на кампанию / Количество привлечённых пользователей`
--Бизнес-влияние: Критически важно для понимания юнит-экономики. Должно быть меньше LTV для прибыльного роста.
--Модель атрибуции: Прямая связь пользователя с кампанией через `users.campaign_id`. NULL означает органический трафик.
select c.campaign_id, campaign_name,
round(sum(spent)/count(u.user_id), 2) as CAC --Стоимость привлечения клиента
from users u
left join campaigns c on u.campaign_id = c.campaign_id
where u.campaign_id is not NULL
group by c.campaign_id
order by CAC

--5.ROMI (Возврат на маркетинговые инвестиции)
--Формула:((Валовая прибыль - Маркетинговые затраты) / Маркетинговые затраты) 
--Где Валовая прибыль = Выручка - Себестоимость товаров_
--Бизнес-влияние: Измеряет прибыльность маркетинговых кампаний. Положительный ROMI указывает на прибыльные маркетинговые затраты.
with
revenues as (
  select order_id, user_id,
         sum(total_amount) as revenue -- выручка
  from orders
  where status != 'cancelled'
  group by order_id, user_id),
price_cost as (
  select order_id,
         sum(oi.product_id) * p.cost as cost_price -- себестоимость
  from order_items oi
  left join products p using (product_id)
  group by p.cost, order_id),
costs_marketing as (
  select campaign_id, campaign_name,
         sum(spent) as marketing_costs -- маркетинговые затраты
  from campaigns
  group by campaign_id, campaign_name)
select
  campaign_id,
  campaign_name,
  round(
    (sum(revenue) - sum(cost_price) - sum(marketing_costs)) * 1.0 /
    sum(marketing_costs),2) * 100 as POMI
from costs_marketing c
join users using (campaign_id)
join revenues r using (user_id)
join price_cost pc using (order_id)
group by campaign_id, campaign_name
order by POMI desc

--6.DAU/MAU (Коэффициент липкости)
--Формула: Среднее DAU за месяц / MAU за тот же месяц
--Бизнес-влияние: Измеряет липкость продукта (sticky factor). Как часто пользователи возвращаются к продукту.
with sessions as (
  select date_trunc('month', session_date) as period,
    date_trunc('day', session_date) as day_date,
    user_id
  from user_sessions),
mau_dau as (
  select t.period,
    round(avg(daily_DAU), 2) as avg_DAU,
    count(distinct s.user_id) as MAU
  from (select period, day_date,
        count(distinct user_id) as daily_DAU
        from sessions
        group by period, day_date) as t
  join sessions s on t.period = s.period and t.day_date = s.day_date
  group by t.period)
select period::date, avg_DAU, MAU,
  round(avg_DAU * 100.0 / MAU, 2) as sticky_factor
from mau_dau
order by period

--7.Retention Rate (Коэффициент удержания)
--Формула: Пользователи, вернувшиеся через N дней / Общее количество новых пользователей`
--Бизнес-влияние:** Измеряет способность продукта удерживать пользователей. Ключевые периоды: Day 1, Day 7, Day 30 retention.
with
a as
(select u.user_id,
(us.session_date - u.registration_date) as diff,
to_char(u.registration_date, 'YYYY-MM') as cohort
from user_sessions us 
join users u 
on us.user_id = u.user_id)
select cohort,
round(count(distinct case when diff >= 0 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2) as "0 (%)",
round(count(distinct case when diff >= 1 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "1 (%)",
round(count(distinct case when diff >= 7 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "7 (%)",
round(count(distinct case when diff >= 30 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "30 (%)"
from a
group by cohort
order by cohort

--8.ARPU(Средняя выручка с пользователя) и ARPPU (Средняя выручка с платящего пользователя)
--Формула ARPU: `Общая выручка / Общие пользователи` **Формула ARPPU:** `Общая выручка / Только платящие пользователи`
--Бизнес-влияние: Ключевые метрики для эффективности монетизации и потенциала роста выручки.
with t1 as (
select sum(total_amount) as revenue, -- выручка
       user_id
from orders
group by user_id)
select round(sum(t1.revenue) * 1.0 / count(distinct t1.user_id), 2) as ARPPU,  
       round(sum(t1.revenue) * 1.0 / (select count(*) from users), 2) as ARPU  
from users u	   
join t1 using(user_id)

--9.LTV_30d (30-дневная жизненная ценность)
--Формула: `Общая выручка в первые 30 дней / Количество пользователей в когорте`
--Бизнес-влияние: Ранний индикатор ценности клиента. 
--Используется для оптимизации затрат на привлечение и прогнозирования долгосрочной ценности.
with 
user_cohorts as (
  select user_id, campaign_id, registration_date as cohort_date
  from users),
orders_30d as (
  select o.user_id, o.total_amount,
  (o.order_date - uc.cohort_date) as days_registrations
  from orders o
  join user_cohorts uc on o.user_id = uc.user_id
  where status != 'cancelled'
        and (o.order_date - uc.cohort_date) between 0 and 29)  -- заказы в первые 30 дней 
select c.campaign_name,
  count(distinct uc.user_id) as клиенты,
  sum(o.total_amount) as ltv_30d,
  round(sum(o.total_amount) * 1.0 / count(distinct uc.user_id), 2) as ltv_30d_клиент
from campaigns c
join user_cohorts uc on c.campaign_id = uc.campaign_id
left join orders_30d o on uc.user_id = o.user_id
group by c.campaign_name
order by клиенты desc, ltv_30d desc

--Задания для анализа каналов привлечения
--Вопросы для исследования:
--1. Какой канал самый эффективный по CAC? Рассчитайте стоимость привлечения клиента для каждого канала
--ответ Email Новогодние скидки
select
    c.campaign_name,
    c.campaign_id,
    sum(c.spent) as затраты_на_маркетинговую_кампанию,
    count(u.user_id) as количество_привлеченных_пользователей,
    round(sum(c.spent) * 1.0 / nullif(count(u.user_id), 0), 2) as CAC
from campaigns c
left join users u on u.campaign_id = c.campaign_id
group by c.campaign_name, c.campaign_id
order by CAC, затраты_на_маркетинговую_кампанию,количество_привлеченных_пользователей
--соотношение LTV / CAC для определения Эффективности канала
select c.campaign_name,
    sum(c.spent) as затраты,
  count(distinct u.user_id) as клиенты,
    round(avg(o.total_amount), 2) as средний_чек,
    round(sum(c.spent) / nullif(count(distinct u.user_id), 0), 2) AS CAC,
    round(avg(o.total_amount), 2) as LTV,
    round(avg(o.total_amount) / nullif(sum(c.spent) / count(distinct u.user_id), 0), 2) AS LTV_CAC --соотношение LTV / CAC
from campaigns c
left join users u ON u.campaign_id = c.campaign_id
left join orders o ON o.user_id = u.user_id where status != 'cancelled'
group by  c.campaign_name
order by CAC, LTV_CAC desc

--2. Какой канал приносит наибольшую LTV? Ответ: 8 марта Акция
select c.campaign_name,
    sum(c.spent) as затраты,
    count(distinct u.user_id) as клиенты,
    avg(o.total_amount) as средний_чек,
    round(sum(c.spent) / nullif(count(distinct u.user_id), 0), 2) as CAC,
    round(avg(o.total_amount), 2) as LTV,
    round(avg(o.total_amount) / nullif(sum(c.spent) / count(distinct u.user_id), 0), 2) as LTV_CAC
from campaigns c
left join users u on u.campaign_id = c.campaign_id
left join orders o on o.user_id = u.user_id
group by  c.campaign_name
order by LTV desc
--Сравните 30-дневную ценность пользователей по каналам
select c.campaign_name,
   count(distinct u.user_id) as клиенты,
   sum(o.total_amount) as LTV_30d,
   round(sum(o.total_amount) * 1.0 / count(distinct u.user_id), 2) as LTV_30d_клиент
from campaigns c
left join users u using(campaign_id)
left join orders o using(user_id)
where order_date >= (select max(order_date) from orders) - INTERVAL '30 days'
  and order_date <= (select max(order_date) from orders)
group by c.campaign_name
order by клиенты desc, LTV_30d

--3. Где лучший ROMI? Проанализируйте возврат инвестиций по типам кампаний
-- Ответ Yandex Direct Бренд и Yandex Direct Категории

--4. Качество vs Количество: Сопоставьте объем трафика и конверсию в покупки
select us.session_date,
    count(distinct us.session_id) as трафик_сессий,  -- количество уникальных сессий за день
    count(distinct case when o.order_id is not null then us.user_id end) as покупок,  -- число пользователей, совершивших покупку
    round(count(distinct case when o.order_id is not null then us.user_id end) * 100.0 /
        nullif(count(distinct us.session_id), 0),2) as конверсия_в_процентах  -- доля сессий, завершившихся покупкой
from user_sessions us
left join orders o using (user_id)
group by us.session_date
order by us.session_date

--Задания для анализа метрик вовлеченности
--Вопросы для исследования:
--1. Паттерны активности: Как меняется DAU/MAU/Sticky factor по месяцам? Есть ли сезонность?
--

--2. Сегментация по устройствам:*Отличается ли поведение пользователей мобильных и десктопных устройств? 
-- Ответ: Да. активнее всего пользователи мобильных устройств
with sessions as (
  select date_trunc('month', session_date) as period,
    date_trunc('day', session_date) as day_date,
    user_id, device_type
  from user_sessions),
mau_dau as (
  select t.period, t.device_type,
    round(avg(daily_DAU), 2) as avg_DAU,
    count(distinct s.user_id) as MAU
  from (select period, day_date, device_type,
        count(distinct user_id) as daily_DAU
        from sessions
        group by period, day_date, device_type) as t
  join sessions s on t.period = s.period and t.day_date = s.day_date
  group by t.period, t.device_type)
select period::date, avg_DAU, MAU, device_type,
  round(avg_DAU * 100.0 / MAU, 2) as sticky_factor
from mau_dau
order by period

--Задания для анализа монетизации
--Вопросы для исследования:
--1. ARPU vs ARPPU: Как меняются метрики по месяцам? Пик пришелся на март, с апреля идет спад
--Какая доля пользователей совершает покупки?
with t1 as (
select sum(total_amount) as revenue, -- выручка
       date_trunc('month', order_date) as MM,
       user_id
from orders
group by user_id, MM)
select MM::date,
       round(sum(t1.revenue) * 1.0 / count(distinct t1.user_id), 2) as ARPPU,  
       round(sum(t1.revenue) * 1.0 / (select count(*) from users), 2) as ARPU  
from users u	   
join t1 using(user_id)
group by MM
--Какая доля пользователей совершает покупки? 47%
select round(count(distinct o.user_id) * 1.0 / (select count(*) from users), 2) * 100 as perc_paying_users
from orders o	   

--2. Корзина покупок: Какие самые популярные категории товаров, а какие самые прибыльные? 
--ТОП 10 ПОПУЛЯРНЫХ ТОВАРОВ
select sum(quantity) as quantity, product_name as name
from order_items
left join products using(product_id)
where order_id in(select order_id
                 from orders 
				 where status != 'cancelled')
group by product_name
order by quantity desc
limit 10
----ТОП 10 ПРИБЫЛЬНЫХ ТОВАРОВ
select (price - cost) as profit, product_name as name
from products 
order by profit desc
limit 10
--Какой средний чек корзины? 823.52
select round(sum(total_amount) * 1.0 / count(distinct order_id), 2) as AOV
from orders
where status != 'cancelled'
--или
select round(avg(total_amount), 2) as AOV
from orders
where status != 'cancelled'

--3. Временные паттерны: В какие дни недели/время суток больше заказов?
--Распределение количества заказов по дням  СБ, ПТ, ПН -ТОП 3
select count(order_id) as count_orders, 
trim(to_char(order_date::date, 'Day')) as day
from orders
where status != 'cancelled'
group by trim(to_char(order_date::date, 'Day'))
order by count_orders desc    
--Распределение количества заказов по времени суток Пик приходится на 20-21 час
select count(order_id) as count_orders,
  to_char(order_timestamp, 'HH24')::integer as hour
from orders
where status != 'cancelled'
group by to_char(order_timestamp, 'HH24')::integer
order by hour

--4. Повторные покупки: Какой процент пользователей покупает повторно в течение 30 дней? 24,81
with first_shop as (
  select user_id,
    min(order_date) as first_shop_date
  from orders
  where status != 'cancelled'
  group by user_id),
repeat_shop as (
  select distinct fsh.user_id
  from first_shop fsh
  join orders o on fsh.user_id = o.user_id
    and o.order_date > fsh.first_shop_date
    and o.order_date <= fsh.first_shop_date + interval '30 days')
select
  round((count(distinct rs.user_id) * 100.0 / count(distinct fsh.user_id)), 2) as repeat_shop_rate_percent
from first_shop fsh
left join repeat_shop rs using(user_id)

--Продвинутые аналитические задания
--Вопросы для исследования:
--1.Когортный анализ: Как меняется поведение пользователей, зарегистрированных в разные месяцы? 
with
a as
(select u.user_id,
(us.session_date - u.registration_date) as diff,
to_char(u.registration_date, 'YYYY-MM') as cohort
from user_sessions us 
join users u 
on us.user_id = u.user_id
where u.user_id in(select user_id
                 from orders 
				 where status != 'cancelled'))
select cohort,
round(count(distinct case when diff >= 0 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2) as "0 (%)",
round(count(distinct case when diff >= 1 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "1 (%)",
round(count(distinct case when diff >= 3 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "3 (%)",
round(count(distinct case when diff >= 7 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "7 (%)",
round(count(distinct case when diff >= 14 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "14 (%)",
round(count(distinct case when diff >= 30 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "30 (%)",
round(count(distinct case when diff >= 60 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "60 (%)",
round(count(distinct case when diff >= 90 then user_id end) * 100.0 / count(distinct case when diff >= 0 then user_id end), 2)  as "90 (%)"
from a
group by cohort
order by cohort

--Подумайте какие метрики вовлеченности можно проанализировать и какие выводы сделать. 
--ER (коэффициент вовлечённости) — это процент пользователей, которые взаимодействовали с контентом , 
--относительно общего числа подписчиков. 679073.00?????
select round(sum(clicks) * 1.0 / count(user_id), 2) *100 as ER
from users
left join campaigns using(campaign_id)

--EIR (Engagement Impression Rate) 3.0
--EIR измеряет вовлечённость относительно количества показов контента. 
--Это полезно, когда один пользователь может видеть пост несколько раз. 
--Формула расчёта: EIR = (Сумма взаимодействий / Количество показов) × 100
select round(sum(clicks) * 1.0 / sum(impressions), 2) *100 as EIR
from campaigns


--2.Сегментация по поведению: Можно ли выделить группы пользователей по активности? 
--Кто приносит больше выручки? Какие рекомендации можно дать маркетингу и продукту?
--Сегментация по сумме покупок
with user_segments as (
  select user_id,
    sum(total_amount) as total_revenue,
    count(*) as total_orders,
    case
      when sum(total_amount) >= 4000 then 'A: Крупные'
      when sum(total_amount) >= 1000 then 'B: Средние'
      else 'C: Малые'
    end as revenue_segment
  from orders
  where status != 'cancelled'
  group by user_id)
select
  revenue_segment,
  count(*) as user_count,
  round(sum(total_revenue), 2) as segment_revenue,
  round(avg(total_revenue), 2) as avg_revenue_per_user,
  round(avg(total_orders), 1) as avg_orders_per_user
from user_segments
group by revenue_segment
order by revenue_segment

--RFM + LTV
WITH thresholds AS (
  SELECT
    30 AS recency_high,      -- до 30 дней
    60 AS recency_mid,       -- до 60 дней
    4 AS frequency_high,     -- от 4 покупок
    2 AS frequency_mid,      -- от 2 покупок
    4000 AS monetary_high,   -- от 4000 руб.
    1000 AS monetary_mid),
rfm_base AS (
  SELECT 
    user_id,
    (MIN(order_date)::DATE - MAX(order_date)::DATE) AS recency,
    COUNT(*) AS frequency,
    SUM(total_amount) AS monetary
  FROM orders
  WHERE status != 'cancelled'
  GROUP BY user_id),
rfm_scores AS (
  SELECT
    rb.user_id,
    rb.recency,
    rb.frequency,
    rb.monetary,
    -- Recency: чем меньше — тем лучше
    CASE
      WHEN rb.recency <= t.recency_high THEN 3
      WHEN rb.recency <= t.recency_mid  THEN 2
      ELSE 1
    END AS recency_score,
    -- Frequency: чем больше — тем лучше
    CASE
      WHEN rb.frequency >= t.frequency_high THEN 3
      WHEN rb.frequency >= t.frequency_mid  THEN 2
      ELSE 1
    END AS frequency_score,
    -- Monetary: чем больше — тем лучше
    CASE
      WHEN rb.monetary >= t.monetary_high THEN 3
      WHEN rb.monetary >= t.monetary_mid  THEN 2
      ELSE 1
    END AS monetary_score,
    CONCAT(
      CASE
        WHEN rb.recency <= t.recency_high THEN '3'
        WHEN rb.recency <= t.recency_mid  THEN '2'
        ELSE '1'
      END,
      CASE
        WHEN rb.frequency >= t.frequency_high THEN '3'
        WHEN rb.frequency >= t.frequency_mid  THEN '2'
        ELSE '1'
      END,
      CASE
        WHEN rb.monetary >= t.monetary_high THEN '3'
        WHEN rb.monetary >= t.monetary_mid  THEN '2'
        ELSE '1'
      END) AS rfm_segment
  FROM rfm_base rb
  CROSS JOIN thresholds t),
rfm_segments_count AS (
  SELECT
    rfm_segment, 
    ROUND(AVG(monetary), 0) AS avg_ltv,
    COUNT(*) AS customer_count
  FROM rfm_scores
  GROUP BY rfm_segment
  ORDER BY rfm_segment)
SELECT
  rfm_segment AS "Названия строк",
  customer_count AS "Количество по полю RFM",
  avg_ltv as "LTV"
FROM rfm_segments_count
ORDER BY rfm_segment

--Распределение клиентов по RFM-сегментам + Доля в общей выручке
WITH rfm_base AS (
  SELECT user_id,
    (MIN(order_date)::DATE - MAX(order_date)::DATE) AS recency,
    COUNT(*) AS frequency,
    SUM(total_amount) AS monetary
  FROM orders
  WHERE status != 'cancelled'
  GROUP BY user_id),
rfm_scores AS (
  SELECT user_id, recency, frequency, monetary,
    CASE -- Recency (чем меньше — тем лучше)
      WHEN recency <= 30 THEN 3
      WHEN recency <= 60 THEN 2
      ELSE 1
    END AS recency_score,
    CASE -- Frequency (чем больше — тем лучше)
      WHEN frequency >= 4 THEN 3
      WHEN frequency >= 2 THEN 2
      ELSE 1
    END AS frequency_score,
    CASE -- Monetary (чем больше — тем лучше)
      WHEN monetary > 4000 THEN 3
      WHEN monetary > 1000 THEN 2
      ELSE 1
    END AS monetary_score
  FROM rfm_base),
rfm_data AS (
  SELECT user_id, recency, frequency, monetary, recency_score, frequency_score, monetary_score,
    CONCAT(recency_score, frequency_score, monetary_score) AS rfm_segment
  FROM rfm_scores),
total_revenue AS (
  -- Предварительно вычисляем общую выручку для расчёта доли
  SELECT SUM(monetary) AS total_monetary FROM rfm_base)
SELECT rfm_segment,
  COUNT(*) AS client_count,
  ROUND(AVG(r.monetary), 2) AS avg_monetary,
  ROUND((SUM(r.monetary) * 100.0 / tr.total_monetary), 2) AS revenue_share_pct,
  CASE
    WHEN recency_score = 3 AND frequency_score = 3 AND monetary_score = 3 THEN 'Champions'
    WHEN recency_score = 3 AND monetary_score >= 2 THEN 'Loyal Customers'
    WHEN recency_score = 3 THEN 'Recent Customers'
    WHEN recency_score = 1 AND frequency_score >= 2 THEN 'At Risk'
    WHEN recency_score = 1 AND frequency_score = 1 THEN 'Lost'
    ELSE 'Other'
  END AS customer_segment
FROM rfm_data r
JOIN total_revenue tr ON true -- Присоединяем общую выручку
GROUP BY  rfm_segment,  recency_score,  frequency_score,  monetary_score,  tr.total_monetary
ORDER BY revenue_share_pct DESC

--**ТОП-10% клиентов по выручке (A-группа)
WITH client_revenue AS (
  SELECT
    user_id,
	SUM(total_amount) AS total_amount
  FROM orders
  WHERE status != 'cancelled'
  GROUP BY user_id),
ranked AS (
  SELECT
    user_id,
    total_amount,
    SUM(total_amount) OVER () AS total_all,
    SUM(total_amount) OVER (ORDER BY total_amount DESC ROWS UNBOUNDED PRECEDING) AS cumsum
  FROM client_revenue)
SELECT
  COUNT(*) AS clients_in_top_10_percent,
  SUM(total_amount) AS revenue_from_top_10
FROM ranked
WHERE cumsum <= 0.1 * total_all

-- ТОП-5 товаров по выручке
SELECT
  product_name,
  SUM(total_amount) AS revenue,
  COUNT(*) AS order_count
FROM orders
JOIN order_items USING(order_id)
LEFT JOIN products USING(product_id)
GROUP BY product_name
ORDER BY revenue DESC
LIMIT 5