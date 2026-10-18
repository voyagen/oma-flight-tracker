# Flight Tracker

<!-- impeccable:product-schema 1 -->

## Platform
Linux desktop, native Omarchy Quattro plugin (Qt Quick).

## Stack
Omarchy bar-widget QML runtime, Python standard-library flight data helper, native tiled map.

## Users
Travelers and people following friends, family, or other flights. No personal flight is selected on first launch.

## Product Purpose
See the aircraft's reported position, recorded path, countries, major cities, and flight information including arrival times.

## Operating Context
A small plane icon in the desktop topbar opens the flight panel. Flight and departure-date controls allow following other flights.

## Capabilities and Constraints
Real provider observations only. Planned route must not be presented as recorded flight history. Missing coverage and stale observations must be explicit. Public flight feeds require internet access and may be limited or unavailable.

## Brand Commitments
The atlas follows the selected Omarchy theme: theme foreground/background for the panel and controls, theme accent for the observed route and aircraft, and matching light/dark geographic tiles. Country and city labels remain legible, with a quiet flight-information strip. The map should be more beautiful than the referenced Omachron plugin.
