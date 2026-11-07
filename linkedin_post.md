I just finished an end-to-end SQL project, and here's what I found. 📊

I played data analyst for an online store (2,600 orders, 300 customers, 4 product categories) and answered 11 business questions using SQL only.

What I built:
→ A reusable view to keep every query clean
→ Month-over-month growth and 3-month moving averages (LAG, window frames)
→ Customer segmentation with NTILE
→ Pareto, cohort retention and churn-risk analysis
→ Market basket analysis with self-joins

What the data said:
• 37.5% profit margin on ~312K in revenue
• Top 25% of customers drive 56% of revenue
• Revenue's 3-month average fell ~28% from its peak, and new-customer cohorts have almost dried up
• Abuja loses orders to cancellations (11.1%), Lagos to returns (7.8%): same problem on paper, different fix
• Discounts cut profit per order from 27.39 to 18.32 without growing basket size (synthetic data, so I treat this as a method demo, not a universal truth)

The biggest lesson: writing the query is the easy part. The real skill is turning the output into a recommendation someone can act on.

Full code, dataset and write-up on GitHub 👇
[add your GitHub link here]

What would you have analysed differently? I'd love feedback from other analysts.

#SQL #DataAnalytics #DataAnalyst #PortfolioProject #WindowFunctions #Analytics
