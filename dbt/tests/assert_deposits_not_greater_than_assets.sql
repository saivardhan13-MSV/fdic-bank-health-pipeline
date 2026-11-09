-- Units sanity check: catches a $ vs $000s mix-up between columns, which would show
-- up as deposits roughly 1000x assets.
--
-- Deposits CAN legitimately exceed assets: when a bank's equity goes negative (e.g.
-- large unrealized securities losses). The first real run found 80 such bank-quarters
-- at 22 small banks (deposits up to 7.7% above assets), every one with negative equity.
-- So this fails only past 1.5x, or when deposits exceed assets while equity is positive.

select cert, report_date, total_assets_usd, total_deposits_usd, total_equity_usd
from {{ ref('fct_bank_quarterly_financials') }}
where total_deposits_usd > 1.5 * total_assets_usd
   or (total_deposits_usd > total_assets_usd and total_equity_usd >= 0)
