package hscript.thx_semver;

#if !thx.semver
using StringTools;

// Grabbed from https://github.com/fponticelli/thx.semver/tree/bdb191fe7cf745c02a980749906dbf22719e200b

abstract Version(SemVer) from SemVer to SemVer {
  static var VERSION = ~/^(\d+)\.(\d+)\.(\d+)(?:[-]([a-z0-9.-]+))?(?:[+]([a-z0-9.-]+))?$/i;
  @:from public static function stringToVersion(s : String) {
    if(!VERSION.match(s)) throw 'Invalid SemVer format for "$s"';
    var major = Std.parseInt(VERSION.matched(1)),
        minor = Std.parseInt(VERSION.matched(2)),
        patch = Std.parseInt(VERSION.matched(3)),
        pre   = parseIdentifiers(VERSION.matched(4)),
        build = parseIdentifiers(VERSION.matched(5));
    return new Version(major, minor, patch, pre, build);
  }

  @:from public static function arrayToVersion(a : Array<Int>) {
    a = (null == a ? [] : a).map(function(v) return v < 0 ? -v : v)
      .concat([0,0,0])
      .slice(0, 3);
    return new Version(a[0], a[1], a[2], [], []);
  }

  inline function new(major : Int, minor : Int, patch : Int, pre : Array<Identifier>, build : Array<Identifier>)
    this = {
      version : [major, minor, patch],
      pre : pre,
      build : build
    };

  public var major(get, never) : Int;
  public var minor(get, never) : Int;
  public var patch(get, never) : Int;
  public var pre(get, never) : String;
  public var hasPre(get, never) : Bool;
  public var build(get, never) : String;
  public var hasBuild(get, never) : Bool;

  public function nextMajor()
    return new Version(major+1, 0, 0, [], []);

  public function nextMinor()
    return new Version(major, minor+1, 0, [], []);

  public function nextPatch()
    return new Version(major, minor, patch+1, [], []);

  public function nextPre()
    return new Version(major, minor, patch, nextIdentifiers((this : SemVer).pre), []);

  public function nextBuild()
    return new Version(major, minor, patch, (this : SemVer).pre, nextIdentifiers((this : SemVer).build));

  public function withPre(pre : String, ?build : String)
    return new Version(major, minor, patch, parseIdentifiers(pre), parseIdentifiers(build));

  public function withBuild(build : String)
    return new Version(major, minor, patch, this.pre, parseIdentifiers(build));

  public inline function satisfies(rule : VersionRule) : Bool
    return rule.isSatisfiedBy(this);

  @:to public function toString() {
    var v = this.version.join('.');
    if(this.pre.length > 0)
      v += '-$pre';
    if(this.build.length > 0)
      v += '+$build';
    return v;
  }

  @:op(A==B) public function equals(other : Version) {
    if(major != other.major || minor != other.minor || patch != other.patch)
      return false;
    return equalsIdentifiers(this.pre, (other : SemVer).pre);
  }

  @:op(A!=B) public function different(other : Version)
    return !(other.equals(this));

  @:op(A>B) public function greaterThan(other : Version) {
    if(hasPre && other.hasPre) {
      return major == other.major
        && minor == other.minor
        && patch == other.patch
        && greaterThanIdentifiers(this.pre, (other : SemVer).pre);
    } else if(other.hasPre) {
      if(major != other.major)
        return major > other.major;
      if(minor != other.minor)
        return minor > other.minor;
      if(patch != other.patch)
        return patch > other.patch;
      return !hasPre || greaterThanIdentifiers(this.pre, (other : SemVer).pre);
    } else if(!hasPre) {
      if(major != other.major)
        return major > other.major;
      if(minor != other.minor)
        return minor > other.minor;
      if(patch != other.patch)
        return patch > other.patch;
      return greaterThanIdentifiers(this.pre, (other : SemVer).pre);
    } else {
      return false;
    }
  }

  @:op(A>=B) public function greaterThanOrEqual(other : Version)
    return equals(other) || greaterThan(other);

  @:op(A<B) public function lessThan(other : Version)
    return !greaterThanOrEqual(other);

  @:op(A<=B) public function lessThanOrEqual(other : Version)
    return !greaterThan(other);

  inline function get_major() return this.version[0];
  inline function get_minor() return this.version[1];
  inline function get_patch() return this.version[2];


  inline function get_pre() return identifiersToString(this.pre);
  inline function get_hasPre() return this.pre.length > 0;
  inline function get_build() return identifiersToString(this.build);
  inline function get_hasBuild() return this.build.length > 0;

  static function identifiersToString(ids : Array<Identifier>)
    return ids.map(function(id) return switch id {
        case StringId(s): s;
        case IntId(i): '$i';
      }).join('.');

  static function parseIdentifiers(s : String) : Array<Identifier>
    return (null == s ? '' : s).split('.')
      .map(sanitize)
      .filter(function(s) return s != '')
      .map(parseIdentifier);

  static function parseIdentifier(s : String) : Identifier {
    var i = Std.parseInt(s);
    return null == i ? StringId(s) : IntId(i);
  }

  static function equalsIdentifiers(a : Array<Identifier>, b : Array<Identifier>) {
    if(a.length != b.length)
      return false;
    for(i in 0...a.length)
      switch [a[i], b[i]] {
        case [StringId(a), StringId(b)] if(a != b): return false;
        case [IntId(a), IntId(b)] if(a != b): return false;
        case _:
      }
    return true;
  }

  static function greaterThanIdentifiers(a : Array<Identifier>, b : Array<Identifier>) {
    for(i in 0...a.length)
      switch [a[i], b[i]] {
        case [StringId(a), StringId(b)] if(a == b): continue;
        case [IntId(a), IntId(b)] if(a == b): continue;
        case [StringId(a), StringId(b)] if(a > b): return true;
        case [IntId(a), IntId(b)] if(a > b): return true;
        case [StringId(_), IntId(_)]: return true;
        case _: return false;
      }
    return false;
  }

  static function nextIdentifiers(identifiers : Array<Identifier>) : Array<Identifier> {
    var identifiers = identifiers.copy(),
        i = identifiers.length;
    while(--i >= 0) switch (identifiers[i]) {
      case IntId(id):
        identifiers[i] = IntId(id+1);
        break;
      case _:
    }
    if(i < 0) throw 'no numeric identifier found in $identifiers';
    return identifiers;
  }

  static var SANITIZER = ~/[^0-9A-Za-z-]/g;
  static function sanitize(s : String) : String
    return SANITIZER.replace(s, '');
}

enum Identifier {
  StringId(value : String);
  IntId(value : Int);
}

typedef SemVer = {
  version : Array<Int>,
  pre : Array<Identifier>,
  build : Array<Identifier>
}
#else
typedef Version = thx.semver.Version;
typedef Identifier = thx.semver.Version.Identifier;
typedef SemVer = thx.semver.Version.SemVer;
#end