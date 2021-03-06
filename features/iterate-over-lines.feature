Feature: Reading GFF3 files line by line, without parsing

  For this feature, Ruby has direct support. However, it is
  interesting to test this functionality in this parser because
  the reading should happen in D runtime. This feature is
  actually the most basic case of binding the Ruby and the D
  part of the new parser.

  Scenario: reading an example file
    Given I have an example file for iterating over lines
    When I open the file for reading
    Then I should be able to use lines.each to iterate over lines

  Scenario: counting the number of lines in a file
    Given I have an example file for iterating over lines
    When I open the file for reading
    Then I should be able to use lines.count to get the number of lines

  Scenario: can't open a closed file
    Given I have an example file for iterating over lines
    When I open the file for reading
    And close it by calling the close method
    When I try to read from it
    Then I should be informed that the operation is not allowed

