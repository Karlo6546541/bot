# Live home and Prodavač

The initial home view contains broadcasts and scheduled shows. The slogan, persistent introduction and product preview have been removed. Live recommendations rank broadcasts directly, instead of competing with products for the same batch. Products remain under Shop. The default tabs are Uživo, Shop and Pratim; swiping follows that order. Category browsing, auctions, digital products and help remain in the filters menu.

Seller Hub is now labelled Prodavač in the navigation, profile and screen title. Its main action starts a live, followed by product creation, the seller's own active/scheduled shows, orders/shipping, products and payouts. Seller account status and the remaining tools remain accessible. The health summary is compact. Existing route classes, action keys, authentication, seller saving and Stripe behavior remain unchanged.

The source before this change is preserved at commit `51b0aa0d9831d7646b8fc8a4ccacd595e3291a81`, branch `backup/subhasto-before-prodavac-2026-11-04`, and a source archive. The Pages workflow retains all published older copies.

Validation: clean Flutter analysis, the full 350-test suite, and browser coverage for mobile/desktop, live viewing, shops and seller controls. Fixture broadcasts are isolated test data, not production broadcasts. No framework migration or payment backend change is included.
