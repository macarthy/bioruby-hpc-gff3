module bio.gff3;

import std.conv, std.stdio, std.array, std.string, std.range, std.exception;
import std.ascii;
import bio.util, bio.fasta, bio.exceptions;

/**
 * Parses a string of GFF3 data.
 * Returns: a range of records.
 */
auto parse(string data) {
  return new RecordRange!(LazySplitLines)(new LazySplitLines(data));
}

/**
 * Parses a file with GFF3 data.
 * Returns: a range of records.
 */
auto open(string filename) {
  return new RecordRange!(typeof(File.byLine()))(File(filename, "r").byLine());
}

/**
 * Represents a lazy range of GFF3 records from a range of lines.
 * The class takes a type parameter, which is the class or the struct
 * which is used as a data source. It's enough for the data source to
 * support front, popFront() and empty methods to be used by this
 * class.
 */
class RecordRange(SourceRangeType) {
  /**
   * Creates a record range with data as the _data source. data can
   * be any range of lines without newlines and with front, popFront()
   * and empty defined.
   */
  this(SourceRangeType data) {
    this.data = data;
  }

  alias typeof(SourceRangeType.front()) Array;

  /**
   * Return the next record in range.
   * Ignores comments, pragmas and empty lines in the data source
   */
  @property Record front() {
    // TODO: Think about adding a record cache instead of recreating the front
    //       record every time
    return Record(nextLine());
  }

  /**
   * Pops the next record in range.
   */
  void popFront() {
    // First get to a line that has a valid record in it
    nextLine();
    data.popFront();
  }

  /**
   * Return true if no more records left in the range.
   */
  @property bool empty() { 
    return nextLine() is null;
  }

  /**
   * Retrieve a range of FASTA sequences appended to
   * GFF3 data. Works only when there are no more
   * records to fetch, e.g. when empty is true.
   */
  auto getFastaRange() {
    scrollUntilFasta();
    if (empty && fastaMode)
      return new FastaRange!(SourceRangeType)(data);
    else
      return null;
  }

  /**
   * Retrieves the FASTA data at the end of file
   * in a string. Works only when there are no more
   * records to fetch, e.g. when empty is true.
   */
  string getFastaData() {
    // TODO: Add tests for this method
    scrollUntilFasta();
    if (empty && fastaMode) {
      auto fastaData = appender!Array();
      while (!data.empty) {
        fastaData.put(data.front);
        fastaData.put("\n");
        data.popFront();
      }
      return cast(immutable)(fastaData.data);
    } else {
      return null;
    }
  }

  private {
    SourceRangeType data;
    bool fastaMode = false;

    string nextLine() {
      Array line = null;
      if (!data.empty)
        line = data.front;
      while ((isComment(line) || isEmptyLine(line)) && !data.empty && !startOfFASTA(line)) {
        data.popFront();
        if (!data.empty)
          line = data.front;
      }
      if (startOfFASTA(line)) {
        fastaMode = true;
        if (!isFastaHeader(line))
          //Remove ##FASTA line from data source
          data.popFront();
      }
      if (data.empty || fastaMode)
        return null;
      else {
        static if (is(typeof(SourceRangeType.front()) == string)) {
          return line;
        } else {
          return to!string(line);
        }
      }
    }

    /**
     * Skips all the GFF3 records until it gets to the start of
     * the FASTA section or end of file
     */
    void scrollUntilFasta() {
      auto line = data.front;
      while ((!data.empty) && (!startOfFASTA(line))) {
        data.popFront();
        if (!data.empty)
          line = data.front;
      }

      if (startOfFASTA(line)) {
        fastaMode = true;
        if (!isFastaHeader(line))
          //Remove ##FASTA line from data source
          data.popFront();
      }
    }

  }
}

/**
 * Represents a parsed line in a GFF3 file.
 */
struct Record {
  this(string line) {
    parseLine(line);
  }

  /**
   * Parse a line from a GFF3 file and set object values.
   * The line is first split into its parts and then escaped
   * characters are replaced in those fields.
   */
  void parseLine(string line) {
    checkIfNineColumnsPresent(line);
    auto parts = split(line, "\t");

    checkRecordForEmptyFields(parts);
    checkIfValidSeqname(parts[0]);
    checkForCharactersInvalidInAnyField("source", parts[1]);
    checkForCharactersInvalidInAnyField("feature", parts[2]);
    checkIfCoordinatesValid(parts[3], parts[4]);
    checkIfScoreValid(parts[5]);
    checkIfStrandValid(parts[6]);
    checkIfPhaseValid(parts[7]);

    seqname = replaceURLEscapedChars(parts[0]);
    source  = replaceURLEscapedChars(parts[1]);
    feature = replaceURLEscapedChars(parts[2]);
    start   = parts[3];
    end     = parts[4];
    score   = parts[5];
    strand  = parts[6];
    phase   = parts[7];
    parseAttributes(parts[8]);
  }

  string seqname;
  string source;
  string feature;
  string start;
  string end;
  string score;
  string strand;
  string phase;
  string[string] attributes;

  /**
   * Returns the ID attribute from record attributes.
   */
  @property string id() {
    if ("ID" in attributes)
      return attributes["ID"];
    else
      return null;
  }

  /**
   * Returns the Parent attribute from record attributes
   */
  @property string parent() {
    if ("Parent" in attributes)
      return attributes["Parent"];
    else
      return null;
  }

  /**
   * Returns true if the attribute Is_circular is true for
   * this record.
   */
  @property bool isCircular() {
    if ("Is_circular" in attributes)
      return attributes["Is_circular"] == "true";
    else
      return false;
  }

  private {

    void parseAttributes(string attributesField) {
      checkIfFieldNotEmptyString("attributes", attributesField);
      if (attributesField[0] != '.') {
        foreach(attribute; split(attributesField, ";")) {
          if (attribute == "") continue;
          checkIfAttributeHasTwoParts(attribute);
          checkIfAttributeNameValid(attribute);
          auto attributeParts = split(attribute, "=");
          auto attributeName = replaceURLEscapedChars(attributeParts[0]);
          auto attributeValue = replaceURLEscapedChars(attributeParts[1]);
          attributes[attributeName] = attributeValue;
        }
        checkForInvalidIsCircularValues();
      }
    }

    static void checkIfFieldNotEmptyString(string field, string fieldValue) {
      if (fieldValue.length == 0)
        throw new AttributeException("Empty " ~ field ~ " field. Use dot for no attributes.", fieldValue);
    }

    static void checkIfAttributeHasTwoParts(string attribute) {
      if (attribute.count('=') != 1)
        throw new AttributeException("Invalid attribute format", attribute);
    }

    static void checkIfAttributeNameValid(string attribute) {
      if (attribute.indexOf("=") == 0) // attribute name missing
        throw new AttributeException("An attribute value without an attribute name", attribute);
    }

    void checkForInvalidIsCircularValues() {
      if ("Is_circular" in attributes) {
        switch (attributes["Is_circular"]) {
          case "true", "false":
            break; // Value valid
          default:
            throw new AttributeException("Ivalid value for Is_circular attribute", attributes["Is_circular"]);
        }
      }
    }

    static void checkIfNineColumnsPresent(string line) {
      if (line.count("\t") < 8)
        throw new RecordException("A record with invalid number of columns", line);
    }

    static void checkRecordForEmptyFields(string[] fields) {
      foreach(i; 0..8) {
        if (fields[i].length < 1)
          throw new RecordException("Found an empty field in record", fields.join("\t"));
      }
    }

    static void checkIfValidSeqname(string seqname) {
      string validSeqnameChars = cast(immutable(char)[])(std.ascii.letters ~ std.ascii.digits ~ ".:^*$@!+_?-|%");
      foreach(character; seqname) {
        if (validSeqnameChars.indexOf(character) < 0)
          throw new RecordException("Invalid characters in seqname field", seqname);
      }
    }

    static void checkForCharactersInvalidInAnyField(string fieldName, string field) {
      foreach(character; field) {
        if (std.ascii.isControl(character))
          throw new RecordException("Control characters not allowed in field " ~ fieldName, field);
      }
    }

    static void checkIfCoordinatesValid(string start, string end) {
      if (start != ".") {
        foreach(character; start) {
          if (!(character.isDigit()))
            throw new RecordException("Only a dot or digits are allowed in field start", start);
        }
        if (to!long(start) < 1)
          throw new RecordException("Start field can't be a number less then 1", start);
      }
      if (end != ".") {
        foreach(character; start) {
          if (!(character.isDigit()))
            throw new RecordException("Only a dot or digits are allowed in field end", end);
        }
        if (to!long(end) < 1)
          throw new RecordException("End field can't be a number less then 1", start);
      }
      if ((start != ".") && (end != ".")) {
        auto startValue = to!long(start);
        auto endValue = to!long(end);
        if (startValue > endValue)
          throw new RecordException("End can't be less then start field", "start=" ~ start ~ ", end=" ~ end);
      }
    }

    static void checkIfScoreValid(string score) {
      checkForCharactersInvalidInAnyField("score", score);
      if (score != ".") {
        try {
          to!double(score);
        } catch (ConvException e) {
          throw new RecordException("Score field should contain a float value", score);
        }
      }
    }

    static void checkIfStrandValid(string strand) {
      switch(strand) {
        case "+", "-", "?", ".":
          break; // Strand value valid
        default:
          throw new RecordException("Invalid strand field", strand);
          break;
      }
    }

    static void checkIfPhaseValid(string phase) {
      switch(phase) {
        case "0", "1", "2", ".":
          break; // Phase value valid
        default:
          throw new RecordException("Invalid phase field", phase);
          break;
      }
    }
  }
}

private {

  bool isEmptyLine(T)(T[] line) {
    return line.strip() == "";
  }

  bool isComment(T)(T[] line) {
    return indexOf(line, '#') != -1;
  }

  bool startOfFASTA(T)(T[] line) {
    return (line.length >= 1) ? (line.startsWith("##FASTA") || (line[0] == '>')) : false;
  }

  bool isFastaHeader(T)(T[] line) {
    return line[0] == '>';
  }
}

unittest {
  writeln("Testing isComment...");
  assert(isComment("# test") == true);
  assert(isComment("     # test") == true);
  assert(isComment("# test\n") == true);

  writeln("Testing isEmptyLine...");
  assert(isEmptyLine("") == true);
  assert(isEmptyLine("    ") == true);
  assert(isEmptyLine("\n") == true);

  writeln("Testing startOfFASTA...");
  assert(startOfFASTA("##FASTA") == true);
  assert(startOfFASTA(">ctg123") == true);
  assert(startOfFASTA("Test 123") == false);
}

unittest {
  writeln("Testing parseAttributes...");

  // Minimal test
  auto record = Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1");
  assert(record.attributes == [ "ID" : "1" ]);
  // Test splitting multiple attributes
  record = Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1;Parent=45");
  assert(record.attributes == [ "ID" : "1", "Parent" : "45" ]);
  // Test if first splitting and then replacing escaped chars
  record = Record(".\t.\t.\t.\t.\t.\t.\t.\tID%3D=1");
  assert(record.attributes == [ "ID=" : "1"]);
  // Test if parser survives trailing semicolon
  record = Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1;Parent=45;");
  assert(record.attributes == [ "ID" : "1", "Parent" : "45" ]);
  // Test for an attribute with the value of a single space
  record = Record(".\t.\t.\t.\t.\t.\t.\t.\tID= ;");
  assert(record.attributes == [ "ID" : " " ]);
  // Test for an attribute with no value
  record = Record(".\t.\t.\t.\t.\t.\t.\t.\tID=;");
  assert(record.attributes == [ "ID" : "" ]);
  // Test for an attribute without a name; should raise an error
  assertThrown!AttributeException(Record(".\t.\t.\t.\t.\t.\t.\t.\t=123"));
  // Test for invalid attribute field
  assertThrown!AttributeException(Record(".\t.\t.\t.\t.\t.\t.\t.\t123"));
  // Test when one attribute ok and a second is invalid
  assertThrown!AttributeException(Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1;123"));
  // Test if two = characters in one attribute
  assertThrown!AttributeException(Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1;1=2=3"));
  // Test with empty string instead of attributes field
  assertThrown!AttributeException(Record(".\t.\t.\t.\t.\t.\t.\t.\t"));
}

unittest {
  writeln("Testing GFF3 Record...");
  // Test line parsing with a normal line
  auto record = Record("ENSRNOG00000019422\tEnsembl\tgene\t27333567\t27357352\t1.0\t+\t2\tID=ENSRNOG00000019422;Dbxref=taxon:10116;organism=Rattus norvegicus;chromosome=18;name=EGR1_RAT;source=UniProtKB/Swiss-Prot;Is_circular=true");
  with (record) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           ["ENSRNOG00000019422", "Ensembl", "gene", "27333567", "27357352", "1.0", "+", "2"]);
    assert(attributes == [ "ID" : "ENSRNOG00000019422", "Dbxref" : "taxon:10116", "organism" : "Rattus norvegicus", "chromosome" : "18", "name" : "EGR1_RAT", "source" : "UniProtKB/Swiss-Prot", "Is_circular" : "true"]);
  }

  // Test parsing lines with dots - undefined values
  record = Record(".\t.\t.\t.\t.\t.\t.\t.\t.");
  with (record) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           [".", ".", ".", ".", ".", ".", ".", "."]);
    assert(attributes.length == 0);
  }

  // Test parsing lines with escaped characters
  record = Record("EXON%3D00000131935\tASTD%25\texon%26\t27344088\t27344141\t.\t+\t.\tID=EXON%3D00000131935;Parent=TRAN%3B000000%3D17239");
  with (record) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           ["EXON=00000131935", "ASTD%", "exon&", "27344088", "27344141", ".", "+", "."]);
    assert(attributes == ["ID" : "EXON=00000131935", "Parent" : "TRAN;000000=17239"]);
  }

  // Test id() method/property
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1").id == "1");
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\tID=").id == "");
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\t.").id is null);

  // Test isCircular() method/property
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\t.").isCircular == false);
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\tIs_circular=false").isCircular == false);
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\tIs_circular=true").isCircular == true);

  // Test the Parent() method/property
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\t.").parent is null);
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\tParent=test").parent == "test");
  assert(Record(".\t.\t.\t.\t.\t.\t.\t.\tID=1;Parent=test;").parent == "test");

  // Testing for invalid values
  // Test for one column missing
  assertThrown!RecordException(Record(".\t..\t.\t.\t.\t.\t.\t."));
  // Test for random text
  assertThrown!RecordException(Record("Test123"));
  // Test for empty columns
  assertThrown!RecordException(Record("\t.\t.\t.\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t\t.\t.\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t\t.\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\t\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\t.\t\t."));
  // Test for invalid characters in all fields
  assertThrown!RecordException(Record("\0\t.\t.\t.\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t\0\t.\t.\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t\0\t.\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t\0\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t\0\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t\0\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\t\0\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\t.\t\0\t."));
  // Test for invalid characters in seqname
  assertThrown!RecordException(Record(">\t.\t.\t.\t.\t.\t.\t.\t."));
  // Test for start and end fields with invalid values
  assertThrown!RecordException(Record(".\t.\t.\t-5\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t0\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t-4\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t0\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t5\t4\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\ta\t.\t.\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\tb\t.\t.\t.\t."));
  // Test for score field with invalid values
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\tabc\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t1.0abc\t.\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\tabc1.0\t.\t.\t."));
  // Test for strand field with invalid values
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\t+-\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\ta\t.\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\t+\0\t.\t."));
  // Test for phase field with invalid values
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\t.\ta\t."));
  assertThrown!RecordException(Record(".\t.\t.\t.\t.\t.\t.\t12\t."));
  // Test for invalid values in Is_circular
  assertThrown!AttributeException(Record(".\t.\t.\t.\t.\t.\t.\t.\tIs_circular=invalid"));
}

unittest {
  writeln("Testing parsing strings with parse function and RecordRange...");

  // Retrieve test file into a string
  File gff3File;
  gff3File.open("./test/data/records.gff3", "r");
  auto data = gff3File.read();

  // Parse data
  auto records = parse(data);
  auto record1 = records.front; records.popFront();
  auto record2 = records.front; records.popFront();
  auto record3 = records.front; records.popFront();
  assert(records.empty == true);

  // Check the results
  with(record1) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           ["ENSRNOG00000019422", "Ensembl", "gene", "27333567", "27357352", "1.0", "+", "2"]);
    assert(attributes == [ "ID" : "ENSRNOG00000019422", "Dbxref" : "taxon:10116", "organism" : "Rattus norvegicus", "chromosome" : "18", "name" : "EGR1_RAT", "source" : "UniProtKB/Swiss-Prot", "Is_circular" : "true"]);
  }
  with(record2) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           [".", ".", ".", ".", ".", ".", ".", "."]);
    assert(attributes.length == 0);
  }
  with(record3) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           ["EXON=00000131935", "ASTD%", "exon&", "27344088", "27344141", ".", "+", "."]);
    assert(attributes == ["ID" : "EXON=00000131935", "Parent" : "TRAN;00000017239"]);
  }

  // Test scrolling to FASTA data
  records = parse(data);
  assert(records.getFastaData() ==
      ">ctg123\n" ~
      "cttctgggcgtacccgattctcggagaacttgccgcaccattccgccttg\n" ~
      "tgttcattgctgcctgcatgttcattgtctacctcggctacgtgtggcta\n" ~
      "tctttcctcggtgccctcgtgcacggagtcgagaaaccaaagaacaaaaa\n" ~
      "aagaaattaaaatatttattttgctgtggtttttgatgtgtgttttttat\n" ~
      "aatgatttttgatgtgaccaattgtacttttcctttaaatgaaatgtaat\n" ~
      "cttaaatgtatttccgacgaattcgaggcctgaaaagtgtgacgccattc\n" ~
      "gtatttgatttgggtttactatcgaataatgagaattttcaggcttaggc\n" ~
      "ttaggcttaggcttaggcttaggcttaggcttaggcttaggcttaggctt\n" ~
      "aggcttaggcttaggcttaggcttaggcttaggcttaggcttaggcttag\n" ~
      "aatctagctagctatccgaaattcgaggcctgaaaagtgtgacgccattc\n" ~
      ">cnda0123\n" ~
      "ttcaagtgctcagtcaatgtgattcacagtatgtcaccaaatattttggc\n" ~
      "agctttctcaagggatcaaaattatggatcattatggaatacctcggtgg\n" ~
      "aggctcagcgctcgatttaactaaaagtggaaagctggacgaaagtcata\n" ~
      "tcgctgtgattcttcgcgaaattttgaaaggtctcgagtatctgcatagt\n" ~
      "gaaagaaaaatccacagagatattaaaggagccaacgttttgttggaccg\n" ~
      "tcaaacagcggctgtaaaaatttgtgattatggttaaagg\n\n\n");
}

unittest {
  writeln("Testing parsing strings with open function and RecordRange...");

  // Parse file
  auto records = open("./test/data/records.gff3");
  auto record1 = records.front; records.popFront();
  auto record2 = records.front; records.popFront();
  auto record3 = records.front; records.popFront();
  assert(records.empty == true);

  // Check the results
  with(record1) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           ["ENSRNOG00000019422", "Ensembl", "gene", "27333567", "27357352", "1.0", "+", "2"]);
    assert(attributes == [ "ID" : "ENSRNOG00000019422", "Dbxref" : "taxon:10116", "organism" : "Rattus norvegicus", "chromosome" : "18", "name" : "EGR1_RAT", "source" : "UniProtKB/Swiss-Prot", "Is_circular" : "true"]);
  }
  with(record2) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           [".", ".", ".", ".", ".", ".", ".", "."]);
    assert(attributes.length == 0);
  }
  with(record3) {
    assert([seqname, source, feature, start, end, score, strand, phase] ==
           ["EXON=00000131935", "ASTD%", "exon&", "27344088", "27344141", ".", "+", "."]);
    assert(attributes == ["ID" : "EXON=00000131935", "Parent" : "TRAN;00000017239"]);
  }

  // Testing with various files
  uint[string] fileRecordsN = [
      "messy_protein_domains.gff3" : 1009,
      "gff3_with_syncs.gff3" : 19,
      "au9_scaffold_subset.gff3" : 1005,
      "tomato_chr4_head.gff3" : 87,
      "directives.gff3" : 0,
      "hybrid1.gff3" : 6,
      "hybrid2.gff3" : 6,
      "knownGene.gff3" : 15,
      "knownGene2.gff3" : 15,
      "mm9_sample_ensembl.gff3" : 190,
      "tomato_test.gff3" : 249,
      "spec_eden.gff3" : 23,
      "spec_match.gff3" : 3 ];
  foreach(filename, recordsN; fileRecordsN) {
    writeln("  Parsing file ./test/data/" ~ filename ~ "...");
    uint counter = 0;
    foreach(rec; open("./test/data/" ~ filename))
      counter++;
    assert(counter == recordsN);
  }
}

