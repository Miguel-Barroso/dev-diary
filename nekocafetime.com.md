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

---

## 2026-05-25 — `/become-fanclub-member/` Showing Blog Page After WP 7.0 Update

TL;DR: `EP_ROOT` in `add_rewrite_endpoint` was hijacking the page URL at root level, and Content Control had two rules pointing at each other causing a redirect storm.

### 🧠 Background

After updating to WordPress 7.0, visiting `/become-fanclub-member/` stopped showing the intro/CTA page and started showing the blog instead. Logged-in subscriber redirects to `/fanclub-members-area-2/` also broke. Deactivating and reactivating all plugins did nothing.

### 🔍 Root Cause 1 — Blog Page Showing

The `customized-functions` plugin (v1.5.0) registers four custom WooCommerce endpoints via:

```php
add_rewrite_endpoint( 'become-fanclub-member', EP_ROOT | EP_PAGES );
```

`EP_ROOT` tells WordPress to intercept requests to `/become-fanclub-member/` at root level and treat them as a WooCommerce query var endpoint. Since no template handler renders that endpoint, WordPress falls back to the blog/posts page. WP 7.0 appears to have changed the rewrite rule priority or matching behaviour, making this conflict visible when it wasn't before.

The older plugin versions (1.0.0–1.3.0) never had `add_rewrite_endpoint` at all and the My Account menu items worked fine — because `nekocafe_custom_url_endpoint` completely overrides the URL via the `woocommerce_get_endpoint_url` filter, making the rewrite endpoint redundant for URL generation.

### 🔍 Root Cause 2 — Redirect Storm

With Content Control re-enabled, visiting `/become-fanclub-member/` triggered `ERR_TOO_MANY_REDIRECTS`. The network trace revealed a mutual redirect loop:

- Content Control rule on `/become-fanclub-member/` → redirected to `/fanclub-members-area-2/`
- Content Control rule on `/fanclub-members-area-2/` → redirected back to `/become-fanclub-member/`

`/become-fanclub-member/` is a public intro/CTA page and should have **no restriction** in Content Control. Only `/fanclub-members-area-2/` should be restricted (subscribers only), with its redirect target set to `/become-fanclub-member/`.

### ✅ Fix

In `customized-functions.php`, changed all four endpoint registrations from `EP_ROOT | EP_PAGES` to `EP_PAGES` only:

```php
// Before
add_rewrite_endpoint( 'become-fanclub-member', EP_ROOT | EP_PAGES );

// After
add_rewrite_endpoint( 'become-fanclub-member', EP_PAGES );
```

This stops the root-level URL interception while keeping the endpoint registered for WooCommerce's My Account context. Deactivated and reactivated the plugin after upload to flush rewrite rules.

Also took the opportunity to refactor the plugin to v1.6.0: extracted the URL map into a dedicated `nekocafe_get_endpoint_urls()` helper, replacing nested `if/elseif` chains with a simple array lookup.

### 📋 Content Control Rules — Correct Setup

| Page | Restriction | Redirect to |
|------|-------------|-------------|
| `/become-fanclub-member/` | None (public) | — |
| `/fanclub-members-area-2/` | Subscribers only | `/become-fanclub-member/` |

### 📌 Note

If this breaks again after a future WP update, check `EP_ROOT` first. And check Content Control rules for mutual redirects before assuming it's a code problem.
