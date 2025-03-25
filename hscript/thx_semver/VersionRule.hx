package hscript.thx_semver;

#if !thx.semver
using hscript.thx_semver.Version;
using StringTools;

// Grabbed from https://github.com/fponticelli/thx.semver/tree/bdb191fe7cf745c02a980749906dbf22719e200b

abstract VersionRule(VersionComparator) from VersionComparator to VersionComparator {
  static var VERSION = ~/^(>=|<=|[v=><~^])?(\d+|[x*])(?:\.(\d+|[x*]))?(?:\.(\d+|[x*]))?(?:[-]([a-z0-9.-]+))?(?:[+]([a-z0-9.-]+))?$/i;
  @:from public static function stringToVersionRule(s : String) : VersionRule {
    var ors = s.split("||").map(function(comp) {
      comp = comp.trim();
      var p = comp.split(" - ");
      return if(p.length == 1) {
        comp = comp.trim();
        p = (~/\s+/).split(comp);
        if(p.length == 1) {
          if(comp.length == 0) {
            GreaterThanOrEqualVersion(Version.arrayToVersion([0,0,0]).withPre(VERSION.matched(5), VERSION.matched(6)));
          } else if(!VERSION.match(comp)) {
            throw 'invalid single pattern "$comp"';
          } else {
            // one term pattern
            var v:Array<Int> = versionArray(VERSION),
                vf = v.concat([0, 0, 0]).slice(0, 3);
            switch [VERSION.matched(1), v.length] {
              case ["v", 0], ["=", 0], ["", 0], [null, 0]:
                GreaterThanOrEqualVersion(Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6)));
              case ["v", 1], ["=", 1], ["", 1], [null, 1]:
                var version = Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6));
                AndRule(
                  GreaterThanOrEqualVersion(version),
                  LessThanVersion(version.nextMajor())
                );
              case ["v", 2], ["=", 2], ["", 2], [null, 2]:
                var version = Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6));
                AndRule(
                  GreaterThanOrEqualVersion(version),
                  LessThanVersion(version.nextMinor())
                );
              case ["v", 3], ["=", 3], ["", 3], [null, 3]:
                EqualVersion(Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6)));
              case [">", _]:
                GreaterThanVersion(Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6)));
              case [">=", _]:
                GreaterThanOrEqualVersion(Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6)));
              case ["<", _]:
                LessThanVersion(Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6)));
              case ["<=", _]:
                LessThanOrEqualVersion(Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6)));
              case ["~", 1]:
                var version = Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6));
                AndRule(
                  GreaterThanOrEqualVersion(version),
                  LessThanVersion(version.nextMajor())
                );
              case ["~", 2], ["~", 3]:
                var version = Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6));
                AndRule(
                  GreaterThanOrEqualVersion(version),
                  LessThanVersion(version.nextMinor())
                );
              case ["^", 1]:
                var version = Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6));
                AndRule(
                  GreaterThanOrEqualVersion(version),
                  LessThanVersion(version.nextMajor())
                );
              case ["^", 2]:
                var version = Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6));
                AndRule(
                  GreaterThanOrEqualVersion(version),
                  LessThanVersion(version.major == 0 ? version.nextMinor() : version.nextMajor())
                );
              case ["^", 3]:
                var version = Version.arrayToVersion(vf).withPre(VERSION.matched(5), VERSION.matched(6));
                AndRule(
                  GreaterThanOrEqualVersion(version),
                  LessThanVersion(version.major == 0 ? (version.minor == 0 ? version.nextPatch() : version.nextMinor()) : version.nextMajor())
                );
              case [p, _]: throw 'invalid prefix "$p" for rule $comp';
            };
          }
        } else if(p.length == 2) {
          if(!VERSION.match(p[0]))
            throw 'left hand parameter is not a valid version rule "${p[0]}"';
          var lp  = VERSION.matched(1),
              lva = versionArray(VERSION),
              lvf = lva.concat([0, 0, 0]).slice(0, 3),
              lv  = Version.arrayToVersion(lvf).withPre(VERSION.matched(5), VERSION.matched(6));

          if(lp != ">" && lp != ">=")
            throw 'invalid left parameter version prefix "${p[0]}", should be either > or >=';
          if(!VERSION.match(p[1]))
            throw 'left hand parameter is not a valid version rule "${p[0]}"';
          var rp  = VERSION.matched(1),
              rva = versionArray(VERSION),
              rvf = rva.concat([0, 0, 0]).slice(0, 3),
              rv  = Version.arrayToVersion(rvf).withPre(VERSION.matched(5), VERSION.matched(6));
          if(rp != "<" && rp != "<=")
            throw 'invalid right parameter version prefix "${p[1]}", should be either < or <=';

          AndRule(
            lp == ">" ? GreaterThanVersion(lv) : GreaterThanOrEqualVersion(lv),
            rp == "<" ? LessThanVersion(rv) : LessThanOrEqualVersion(rv)
          );
        } else {
          throw 'invalid multi pattern $comp';
        }
      } else if(p.length == 2) {
        if(!VERSION.match(p[0]))
            throw 'left range parameter is not a valid version rule "${p[0]}"';
        if(VERSION.matched(1) != null && VERSION.matched(1) != "")
            throw 'left range parameter should not be prefixed "${p[0]}"';
        var lv = Version.arrayToVersion(versionArray(VERSION).concat([0, 0, 0]).slice(0, 3)).withPre(VERSION.matched(5), VERSION.matched(6));
        if(!VERSION.match(p[1]))
            throw 'right range parameter is not a valid version rule "${p[1]}"';
        if(VERSION.matched(1) != null && VERSION.matched(1) != "")
            throw 'right range parameter should not be prefixed "${p[1]}"';
        var rva = versionArray(VERSION),
            rv = Version.arrayToVersion(rva.concat([0, 0, 0]).slice(0, 3)).withPre(VERSION.matched(5), VERSION.matched(6));

        if(rva.length == 1)
          rv = rv.nextMajor();
        else if(rva.length == 2)
          rv = rv.nextMinor();

        AndRule(
          GreaterThanOrEqualVersion(lv),
          rva.length == 3 ? LessThanOrEqualVersion(rv) : LessThanVersion(rv)
        );
      } else {
        throw 'invalid pattern "$comp"';
      }
    });

    var rule = null;
    while(ors.length > 0) {
      var r = ors.pop();
      if(null == rule)
        rule = r;
      else
        rule = OrRule(r, rule);
    }
    return rule;
  }

  static var IS_DIGITS = ~/^\d+$/;
  static function versionArray(re : EReg) {
    var arr:Array<Int> = [];
    var t:String;
    for(i in 2...5) {
      t = re.matched(i);
      if(null != t && IS_DIGITS.match(t))
        arr.push(Std.parseInt(t));
      else
        break;
    }
    return arr;
  }

  public static function versionRuleIsValid(rule : String)
    return try stringToVersionRule(rule) != null catch(e : Dynamic) false;

  public function isSatisfiedBy(version : Version) : Bool {
    return switch this {
      case EqualVersion(ver):
        version == ver;
      case GreaterThanVersion(ver):
        version > ver;
      case GreaterThanOrEqualVersion(ver):
        version >= ver;
      case LessThanVersion(ver):
        version < ver;
      case LessThanOrEqualVersion(ver):
        version <= ver;
      case AndRule(a, b):
        (a : VersionRule).isSatisfiedBy(version) && (b : VersionRule).isSatisfiedBy(version);
      case OrRule(a, b):
        (a : VersionRule).isSatisfiedBy(version) || (b : VersionRule).isSatisfiedBy(version);
    };
  }

  @:to public function toString() : String
    return switch ((this : VersionComparator)) {
      case EqualVersion(ver):
        ver;
      case GreaterThanVersion(ver):
        '>$ver';
      case GreaterThanOrEqualVersion(ver):
        '>=$ver';
      case LessThanVersion(ver):
        '<$ver';
      case LessThanOrEqualVersion(ver):
        '<=$ver';
      case AndRule(a, b): {
        (a : VersionRule) + ' ' + (b : VersionRule);
      }
      case OrRule(a, b):
        (a : VersionRule) + ' || ' + (b : VersionRule);
    };
}

enum VersionComparator {
  EqualVersion(ver : Version);
  GreaterThanVersion(ver : Version);
  GreaterThanOrEqualVersion(ver : Version);
  LessThanVersion(ver : Version);
  LessThanOrEqualVersion(ver : Version);
  AndRule(a : VersionComparator, b : VersionComparator);
  OrRule(a : VersionComparator, b : VersionComparator);
}
#else
typedef VersionRule = thx.semver.VersionRule;
typedef VersionComparator = thx.semver.VersionRule.VersionComparator;
#end