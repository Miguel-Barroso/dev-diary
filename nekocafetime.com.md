🛠️ WooCommerce + WPML Product Variations Troubleshooting

TL;DR: Broken product variations on translated product pages? Here's how I punched it into working again. 😤🔥

🧠 Background

When translating WooCommerce products using WPML, I noticed:

    Translated products were missing variations

    Prices were incorrect or not shown

    Dropdowns were empty or broken

Turns out WPML can get too clever with how it links translated products and their attributes.

✅ Solution

    Edit the product in either the original or translated language.

    In the sidebar, locate the dropdown labeled "Translation of:"

    Set it to --None--
    👉 This unlinks the translated product from the original.

    Once unlinked:

        Edit variations as needed.

        Ensure attributes and prices are correct.

        Save and preview the translated product.

    When everything looks good:

        Re-link the product by selecting the original/translation again in the "Translation of:" dropdown.

💡 This lets you override locked/greyed-out settings that were otherwise inaccessible.

🎁 Bonus Tips

🧩 Attribute sanity check:

    Go to WooCommerce → Attributes

    Make sure each attribute (like “Size”, “Color”, etc.) is correctly translated.

⚠️ IMPORTANT: The admin language (e.g., Japanese or English) determines how attributes are displayed and edited.

So if:

    Your admin language is Japanese,

    But attributes (e.g., Color) appear in English,

    You need to delete, re-add, or re-link translations manually from this page.

🛑 DO NOT rely on WPML Translation Manager for variations or attributes.
It's… garbage for this use case. 🗑️💥

📌 Final Note

This issue burned quite a few hours of my life.
Hopefully, next time I read this before I start swearing at the screen. 🧘‍♂️🖥️💢
