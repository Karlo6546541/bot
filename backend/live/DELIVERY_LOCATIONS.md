# Parcel location catalogue

The purchase popup and online orders allow courier delivery or a BOX NOW locker.
`commerce_search_lockers` reads active database locations and ranks the buyer's
address by postcode, city and matching address words. It does not geocode the
buyer or claim an exact nearest distance. No buyer address is sent to BOX NOW.
The client sends only the selected database ID; `commerce_choose_shipping`
validates it and saves the provider ID and canonical destination address.

`delivery-lockers-sync` reads the public catalogue used by the official BOX NOW
map widget: `https://globallockersprod.z28.web.core.windows.net/PROD/{country}/lockers/all.json`.
Supported catalogues: Croatia, Slovenia, Greece, Bulgaria and Cyprus. Other
countries can use courier delivery. The source is public and needs no API key.
The sync accepts only the private scheduler header, not user JWTs. Apply
`sql/delivery_locations_schedule.sql` once to refresh daily at 03:15 UTC.
A failed or unexpectedly small import retains the previous catalogue.

Locations are real; carrier booking and tracking remain in the existing demo
mode. Selecting a location does not book a shipment or charge the buyer. Actual
carrier booking requires a separate contracted carrier integration.
