package dev.hegel;

/** Span label constants matching the hegel-core protocol specification. */
public final class Labels {

  private Labels() {}

  public static final long LIST = 1;
  public static final long LIST_ELEMENT = 2;
  public static final long SET = 3;
  public static final long SET_ELEMENT = 4;
  public static final long MAP = 5;
  public static final long MAP_ENTRY = 6;
  public static final long TUPLE = 7;
  public static final long ONE_OF = 8;
  public static final long OPTIONAL = 9;
  public static final long FIXED_DICT = 10;
  public static final long FLAT_MAP = 11;
  public static final long FILTER = 12;
  public static final long MAPPED = 13;
  public static final long SAMPLED_FROM = 14;
}
