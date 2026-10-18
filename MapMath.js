.pragma library

var MAX_LATITUDE = 85.05112878;

function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
function wrap(value) { return ((value % 1) + 1) % 1; }
function near(value, reference) { return value + Math.round(reference - value); }
function valid(point) {
    return point && point.lat !== null && point.lon !== null
            && isFinite(Number(point.lat)) && isFinite(Number(point.lon))
            && Math.abs(Number(point.lat)) <= 90 && Math.abs(Number(point.lon)) <= 180;
}
function project(point) {
    var latitude = clamp(Number(point.lat), -MAX_LATITUDE, MAX_LATITUDE) * Math.PI / 180;
    return {x: (Number(point.lon) + 180) / 360,
            y: (1 - Math.log(Math.tan(latitude) + 1 / Math.cos(latitude)) / Math.PI) / 2};
}
function greatCircle(origin, destination) {
    if (!valid(origin) || !valid(destination)) return [];
    var aLat = Number(origin.lat) * Math.PI / 180;
    var aLon = Number(origin.lon) * Math.PI / 180;
    var bLat = Number(destination.lat) * Math.PI / 180;
    var bLon = Number(destination.lon) * Math.PI / 180;
    var a = [Math.cos(aLat) * Math.cos(aLon), Math.cos(aLat) * Math.sin(aLon), Math.sin(aLat)];
    var b = [Math.cos(bLat) * Math.cos(bLon), Math.cos(bLat) * Math.sin(bLon), Math.sin(bLat)];
    var angle = Math.acos(clamp(a[0]*b[0] + a[1]*b[1] + a[2]*b[2], -1, 1));
    var result = [];
    // Use a deterministic perpendicular for the otherwise undefined antipodal route.
    var tangent = [b[0] - a[0]*Math.cos(angle), b[1] - a[1]*Math.cos(angle), b[2] - a[2]*Math.cos(angle)];
    var length = Math.sqrt(tangent[0]*tangent[0] + tangent[1]*tangent[1] + tangent[2]*tangent[2]);
    if (length < 1e-8) {
        tangent = Math.abs(a[2]) < 0.9 ? [-a[1], a[0], 0] : [0, -a[2], a[1]];
        length = Math.sqrt(tangent[0]*tangent[0] + tangent[1]*tangent[1] + tangent[2]*tangent[2]);
    }
    for (var i = 0; i <= 128; ++i) {
        var t = i / 128;
        var c = Math.cos(angle*t), s = Math.sin(angle*t) / length;
        var x = a[0]*c + tangent[0]*s, y = a[1]*c + tangent[1]*s, z = a[2]*c + tangent[2]*s;
        result.push({lat: Math.atan2(z, Math.sqrt(x*x + y*y))*180/Math.PI,
                        lon: Math.atan2(y, x)*180/Math.PI});
    }
    result[0] = origin;
    result[result.length - 1] = destination;
    return result;
}
function bounds(points) {
    var first = null, lowX = Infinity, highX = -Infinity, lowY = Infinity, highY = -Infinity;
    for (var i = 0; i < points.length; ++i) {
        if (!valid(points[i])) continue;
        var p = project(points[i]);
        if (first === null) first = p.x;
        p.x = near(p.x, first);
        lowX = Math.min(lowX, p.x); highX = Math.max(highX, p.x);
        lowY = Math.min(lowY, p.y); highY = Math.max(highY, p.y);
    }
    return first === null ? null : {x: (lowX + highX)/2, y: (lowY + highY)/2,
                                    width: highX - lowX, height: highY - lowY};
}
