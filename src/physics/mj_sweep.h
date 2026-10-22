#pragma once

// Continuous translation of a sphere against a convex primitive. No temporal
// sampling: squared distance to a closed convex set is convex and C1. Its
// directional derivative is monotone, so a bracketed derivative root locates
// the global minimum on the entire segment, including a zero-width tangency.
#include <algorithm>
#include <cmath>
#include <limits>

namespace gmj_sweep {
enum class Kind { sphere, box, cylinder };
struct Vec {
 double x, y, z;
 Vec operator+(Vec b) const { return {x+b.x,y+b.y,z+b.z}; }
 Vec operator-(Vec b) const { return {x-b.x,y-b.y,z-b.z}; }
 Vec operator*(double s) const { return {x*s,y*s,z*s}; }
 double dot(Vec b) const { return x*b.x+y*b.y+z*b.z; }
 double length() const { return std::hypot(x,y,z); }
};
struct Primitive { Kind kind; Vec size; };
inline Vec closest(const Primitive &g, Vec p) {
 if (g.kind==Kind::box) return {std::clamp(p.x,-g.size.x,g.size.x),std::clamp(p.y,-g.size.y,g.size.y),std::clamp(p.z,-g.size.z,g.size.z)};
 if (g.kind==Kind::sphere) {
   double n=p.length(); return n>g.size.x ? p*(g.size.x/n) : p;
 }
 double radial=std::hypot(p.x,p.y), scale=radial>g.size.x ? g.size.x/radial : 1;
 return {p.x*scale,p.y*scale,std::clamp(p.z,-g.size.y,g.size.y)};
}
struct Result {
 bool valid=true, hit=false, initial_overlap=false;
 double safe=1, unsafe=1;
 Vec point{}, normal{};
};
inline Result sphere(const Primitive &g, Vec start, Vec motion, double radius) {
 Result result;
 double speed=motion.length();
 auto delta=[&](double t) { Vec p=start+motion*t; return p-closest(g,p); };
 Vec d0=delta(0);
 double r2=radius*radius;
 if (d0.dot(d0)<r2) { result.initial_overlap=true; return result; }
 if (speed==0 || d0.dot(motion)>=0) return result;
 // The derivative of squared distance is 2 * (p - projection(p)) . motion.
 double left=0,right=1;
 if (delta(1).dot(motion)>0) {
   for(int i=0;i<96;++i) {
     double mid=(left+right)*.5; if(mid==left || mid==right) break;
     if(delta(mid).dot(motion)<0) left=mid; else right=mid;
   }
 } else left=right=1;
 double minimum=(left+right)*.5;
 Vec dm=delta(minimum);
 double distance=dm.length();
 double roundoff=128*std::numeric_limits<double>::epsilon()*
     std::max({1.0,start.length(),speed,g.size.length(),radius});
 if(distance>radius) {
   // Lipschitz lower bound over the minimizer bracket certifies a miss.
   // Ambiguous grazing roundoff fails explicitly instead of reporting [1,1].
   result.valid=distance-speed*(right-left)-roundoff>radius;
   return result;
 }
 // A distance evaluation at the global minimum brackets the earliest entry
 // to floating-point precision; the caller must validate the final ABI pose.
 // This also catches arbitrarily short intersection intervals and tangencies.
 left=0; right=minimum;
 if(d0.dot(d0)<=r2) right=0;
 else for(int i=0;i<96;++i) {
   double mid=(left+right)*.5; if(mid==left || mid==right) break;
   Vec d=delta(mid);
   if(d.dot(d)>r2) left=mid; else right=mid;
 }
 result.hit=true; result.safe=left; result.unsafe=right;
 Vec p=start+motion*right;
 result.point=closest(g,p);
 Vec n=p-result.point; double length=n.length();
 if(length==0 || !std::isfinite(length)) { result.valid=false; return result; }
 result.normal=n*(1/length);
 return result;
}
// One linear signed supporting-plane distance, valid for a fixed orientation.
inline Result plane(double gap, double normal_motion) {
 Result result;
 if(gap<0) { result.initial_overlap=true; return result; }
 if(normal_motion>=0) return result;
 double t=gap/-normal_motion;
 if(t>1) return result;
 result.hit=true; result.safe=result.unsafe=std::max(0.0,t); return result;
}
} // namespace gmj_sweep
