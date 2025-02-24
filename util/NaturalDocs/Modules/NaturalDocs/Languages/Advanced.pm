###############################################################################
#
#   Class: NaturalDocs::Languages::Advanced
#
###############################################################################
#
#   The base class for all languages that have full support in Natural Docs.  Each one will have a custom parser capable
#   of documenting undocumented aspects of the code.
#
###############################################################################

# This file is part of Natural Docs, which is Copyright © 2003-2010 Greg Valure
# Natural Docs is licensed under version 3 of the GNU Affero General Public License (AGPL)
# Refer to License.txt for the complete details

use strict;
use integer;

use NaturalDocs::Languages::Advanced::Scope;
use NaturalDocs::Languages::Advanced::ScopeChange;

package NaturalDocs::Languages::Advanced;

use base 'NaturalDocs::Languages::Base';


#############################################################################
# Group: Implementation

#
#   Constants: Members
#
#   The class is implemented as a blessed arrayref.  The following constants are used as indexes.
#
#   TOKENS - An arrayref of tokens used in all the <Parsing Functions>.
#   SCOPE_STACK - An arrayref of <NaturalDocs::Languages::Advanced::Scope> objects serving as a scope stack for parsing.
#                            There will always be one available, with a symbol of undef, for the top level.
#   SCOPE_RECORD - An arrayref of <NaturalDocs::Languages::Advanced::ScopeChange> objects, as generated by the scope
#                              stack.  If there is more than one change per line, only the last is stored.
#   AUTO_TOPICS - An arrayref of <NaturalDocs::Parser::ParsedTopics> generated automatically from the code.
#
use NaturalDocs::DefineMembers 'TOKENS', 'SCOPE_STACK', 'SCOPE_RECORD', 'AUTO_TOPICS';


#############################################################################
# Group: Functions

#
#   Function: New
#
#   Creates and returns a new object.
#
#   Parameters:
#
#       name - The name of the language.
#
sub New #(name)
    {
    my ($package, @parameters) = @_;

    my $object = $package->SUPER::New(@parameters);
    $object->[TOKENS] = undef;
    $object->[SCOPE_STACK] = undef;
    $object->[SCOPE_RECORD] = undef;

    return $object;
    };


# Function: Tokens
# Returns the tokens found by <ParseForCommentsAndTokens()>.
sub Tokens
    {  return $_[0]->[TOKENS];  };

# Function: SetTokens
# Replaces the tokens.
sub SetTokens #(tokens)
    {  $_[0]->[TOKENS] = $_[1];  };

# Function: ClearTokens
#  Resets the token list.  You may want to do this after parsing is over to save memory.
sub ClearTokens
    {  $_[0]->[TOKENS] = undef;  };

# Function: AutoTopics
# Returns the arrayref of automatically generated topics, or undef if none.
sub AutoTopics
    {  return $_[0]->[AUTO_TOPICS];  };

# Function: AddAutoTopic
# Adds a <NaturalDocs::Parser::ParsedTopic> to <AutoTopics()>.
sub AddAutoTopic #(topic)
    {
    my ($self, $topic) = @_;
    if (!defined $self->[AUTO_TOPICS])
        {  $self->[AUTO_TOPICS] = [ ];  };
    push @{$self->[AUTO_TOPICS]}, $topic;
    };

# Function: ClearAutoTopics
# Resets the automatic topic list.  Not necessary if you call <ParseForCommentsAndTokens()>.
sub ClearAutoTopics
    {  $_[0]->[AUTO_TOPICS] = undef;  };

# Function: ScopeRecord
# Returns an arrayref of <NaturalDocs::Languages::Advanced::ScopeChange> objects describing how and when the scope
# changed thoughout the file.  There will always be at least one entry, which will be for line 1 and undef as the scope.
sub ScopeRecord
    {  return $_[0]->[SCOPE_RECORD];  };



###############################################################################
#
#   Group: Parsing Functions
#
#   These functions are good general language building blocks.  Use them to create your language-specific parser.
#
#   All functions work on <Tokens()> and assume it is set by <ParseForCommentsAndTokens()>.
#


#
#   Function: ParseForCommentsAndTokens
#
#   Loads the passed file, sends all appropriate comments to <NaturalDocs::Parser->OnComment()>, and breaks the rest into
#   an arrayref of tokens.  Tokens are defined as
#
#   - All consecutive alphanumeric and underscore characters.
#   - All consecutive whitespace.
#   - A single line break.  It will always be "\n"; you don't have to worry about platform differences.
#   - A single character not included above, which is usually a symbol.  Multiple consecutive ones each get their own token.
#
#   The result will be placed in <Tokens()>.
#
#   Parameters:
#
#       sourceFile - The source <FileName> to load and parse.
#       lineCommentSymbols - An arrayref of symbols that designate line comments, or undef if none.
#       blockCommentSymbols - An arrayref of symbol pairs that designate multiline comments, or undef if none.  Symbol pairs are
#                                            designated as two consecutive array entries, the opening symbol appearing first.
#       javadocLineCommentSymbols - An arrayref of symbols that designate the start of a JavaDoc comment, or undef if none.
#       javadocBlockCommentSymbols - An arrayref of symbol pairs that designate multiline JavaDoc comments, or undef if none.
#
#   Notes:
#
#       - This function automatically calls <ClearAutoTopics()> and <ClearScopeStack()>.  You only need to call those functions
#         manually if you override this one.
#       - To save parsing time, all comment lines sent to <NaturalDocs::Parser->OnComment()> will be replaced with blank lines
#         in <Tokens()>.  It's all the same to most languages.
#
sub ParseForCommentsAndTokens #(FileName sourceFile, string[] lineCommentSymbols, string[] blockCommentSymbols, string[] javadocLineCommentSymbols, string[] javadocBlockCommentSymbols)
    {
    my ($self, $sourceFile, $lineCommentSymbols, $blockCommentSymbols,
           $javadocLineCommentSymbols, $javadocBlockCommentSymbols) = @_;

    open(SOURCEFILEHANDLE, '<' . $sourceFile)
        or die "Couldn't open input file " . $sourceFile . "\n";

    my $lineReader = NaturalDocs::LineReader->New(\*SOURCEFILEHANDLE);

    my $tokens = [ ];
    $self->SetTokens($tokens);

    # For convenience.
    $self->ClearAutoTopics();
    $self->ClearScopeStack();


    # Load and preprocess the file

    my @lines = $lineReader->GetAll();
    close(SOURCEFILEHANDLE);

    $self->PreprocessFile(\@lines);


    # Go through the file

    my $lineIndex = 0;

    while ($lineIndex < scalar @lines)
        {
        my $line = $lines[$lineIndex];

        my @commentLines;
        my $commentLineNumber;
        my $isJavaDoc;
        my $closingSymbol;


        # Retrieve single line comments.  This leaves $lineIndex at the next line.

        if ( ($isJavaDoc = $self->StripOpeningJavaDocSymbols(\$line, $javadocLineCommentSymbols)) ||
              $self->StripOpeningSymbols(\$line, $lineCommentSymbols))
            {
            $commentLineNumber = $lineIndex + 1;

            do
                {
                push @commentLines, $line;
                push @$tokens, "\n";

                $lineIndex++;

                if ($lineIndex >= scalar @lines)
                    {  goto EndDo;  };

                $line = $lines[$lineIndex];
                }
            while ($self->StripOpeningSymbols(\$line, $lineCommentSymbols));

            EndDo:  # I hate Perl sometimes.
            }


        # Retrieve multiline comments.  This leaves $lineIndex at the next line.

        elsif ( ($isJavaDoc = $self->StripOpeningJavaDocBlockSymbols(\$line, $javadocBlockCommentSymbols)) ||
                 ($closingSymbol = $self->StripOpeningBlockSymbols(\$line, $blockCommentSymbols)) )
            {
            $commentLineNumber = $lineIndex + 1;

            if ($isJavaDoc)
                {  $closingSymbol = $isJavaDoc;  };

            # Note that it is possible for a multiline comment to start correctly but not end so.  We want those comments to stay in
            # the code.  For example, look at this prototype with this splint annotation:
            #
            # int get_array(integer_t id,
            #                    /*@out@*/ array_t array);
            #
            # The annotation starts correctly but doesn't end so because it is followed by code on the same line.

            my ($lineRemainder, $isMultiLine);

            for (;;)
                {
                $lineRemainder = $self->StripClosingSymbol(\$line, $closingSymbol);

                push @commentLines, $line;

                #  If we found an end comment symbol...
                if (defined $lineRemainder)
                    {  last;  };

                push @$tokens, "\n";
                $lineIndex++;
                $isMultiLine = 1;

                if ($lineIndex >= scalar @lines)
                    {  last;  };

                $line = $lines[$lineIndex];
                };

            if ($lineRemainder !~ /^[ \t]*$/)
                {
                # If there was something past the closing symbol this wasn't an acceptable comment.

                if ($isMultiLine)
                    {  $self->TokenizeLine($lineRemainder);  }
                else
                    {
                    # We go back to the original line if it wasn't a multiline comment because we want the comment to stay in the
                    # code.  Otherwise the /*@out@*/ from the example would be removed.
                    $self->TokenizeLine($lines[$lineIndex]);
                    };

                @commentLines = ( );
                }
            else
                {
                push @$tokens, "\n";
                };

            $lineIndex++;
            }


        # Otherwise just add it to the code.

        else
            {
            $self->TokenizeLine($line);
            $lineIndex++;
            };


        # If there were comments, send them to Parser->OnComment().

        if (scalar @commentLines)
            {
            NaturalDocs::Parser->OnComment(\@commentLines, $commentLineNumber, $isJavaDoc);
            @commentLines = ( );
            $isJavaDoc = undef;
            };

        # $lineIndex was incremented by the individual code paths above.

        };  # while ($lineIndex < scalar @lines)
    };


#
#   Function: PreprocessFile
#
#   An overridable function if you'd like to preprocess the file before it goes into <ParseForCommentsAndTokens()>.
#
#   Parameters:
#
#       lines - An arrayref to the file's lines.  Each line has its line break stripped off, but is otherwise untouched.
#
sub PreprocessFile #(lines)
    {
    };


#
#   Function: TokenizeLine
#
#   Converts the passed line to tokens as described in <ParseForCommentsAndTokens> and adds them to <Tokens()>.  Also
#   adds a line break token after it.
#
sub TokenizeLine #(line)
    {
    my ($self, $line) = @_;
    push @{$self->Tokens()}, $line =~ /(\w+|[ \t]+|.)/g, "\n";
    };


#
#   Function: TryToSkipString
#
#   If the position is on a string delimiter, moves the position to the token following the closing delimiter, or past the end of the
#   tokens if there is none.  Assumes all other characters are allowed in the string, the delimiter itself is allowed if it's preceded by
#   a backslash, and line breaks are allowed in the string.
#
#   Parameters:
#
#       indexRef - A reference to the position's index into <Tokens()>.
#       lineNumberRef - A reference to the position's line number.
#       openingDelimiter - The opening string delimiter, such as a quote or an apostrophe.
#       closingDelimiter - The closing string delimiter, if different.  If not defined, assumes the same as openingDelimiter.
#       startContentIndexRef - A reference to a variable in which to store the index of the first token of the string's content.
#                                         May be undef.
#       endContentIndexRef - A reference to a variable in which to store the index of the end of the string's content, which is one
#                                        past the last index of content.  May be undef.
#
#   Returns:
#
#       Whether the position was on the passed delimiter or not.  The index, line number, and content index ref variables will be
#       updated only if true.
#
sub TryToSkipString #(indexRef, lineNumberRef, openingDelimiter, closingDelimiter, startContentIndexRef, endContentIndexRef)
    {
    my ($self, $index, $lineNumber, $openingDelimiter, $closingDelimiter, $startContentIndexRef, $endContentIndexRef) = @_;
    my $tokens = $self->Tokens();

    if (!defined $closingDelimiter)
        {  $closingDelimiter = $openingDelimiter;  };

    if ($tokens->[$$index] ne $openingDelimiter)
        {  return undef;  };


    $$index++;
    if (defined $startContentIndexRef)
        {  $$startContentIndexRef = $$index;  };

    while ($$index < scalar @$tokens)
        {
        if ($tokens->[$$index] eq "\\")
            {
            # Skip the token after it.
            $$index += 2;
            }
        elsif ($tokens->[$$index] eq "\n")
            {
            $$lineNumber++;
            $$index++;
            }
        elsif ($tokens->[$$index] eq $closingDelimiter)
            {
            if (defined $endContentIndexRef)
                {  $$endContentIndexRef = $$index;  };

            $$index++;
            last;
            }
        else
            {
            $$index++;
            };
        };

    if ($$index >= scalar @$tokens && defined $endContentIndexRef)
        {  $$endContentIndexRef = scalar @$tokens;  };

    return 1;
    };


#
#   Function: SkipRestOfLine
#
#   Moves the position to the token following the next line break, or past the end of the tokens array if there is none.  Useful for
#   line comments.
#
#   Note that it skips blindly.  It assumes there cannot be anything of interest, such as a string delimiter, between the position
#   and the end of the line.
#
#   Parameters:
#
#       indexRef - A reference to the position's index into <Tokens()>.
#       lineNumberRef - A reference to the position's line number.

sub SkipRestOfLine #(indexRef, lineNumberRef)
    {
    my ($self, $index, $lineNumber) = @_;
    my $tokens = $self->Tokens();

    while ($$index < scalar @$tokens)
        {
        if ($tokens->[$$index] eq "\n")
            {
            $$lineNumber++;
            $$index++;
            last;
            }
        else
            {
            $$index++;
            };
        };
    };


#
#   Function: SkipUntilAfter
#
#   Moves the position to the token following the next occurance of a particular token sequence, or past the end of the tokens
#   array if it never occurs.  Useful for multiline comments.
#
#   Note that it skips blindly.  It assumes there cannot be anything of interest, such as a string delimiter, between the position
#   and the end of the line.
#
#   Parameters:
#
#       indexRef - A reference to the position's index.
#       lineNumberRef - A reference to the position's line number.
#       token - A token that must be matched.  Can be specified multiple times to match a sequence of tokens.
#
sub SkipUntilAfter #(indexRef, lineNumberRef, token, token, ...)
    {
    my ($self, $index, $lineNumber, @target) = @_;
    my $tokens = $self->Tokens();

    while ($$index < scalar @$tokens)
        {
        if ($tokens->[$$index] eq $target[0] && ($$index + scalar @target) <= scalar @$tokens)
            {
            my $match = 1;

            for (my $i = 1; $i < scalar @target; $i++)
                {
                if ($tokens->[$$index+$i] ne $target[$i])
                    {
                    $match = 0;
                    last;
                    };
                };

            if ($match)
                {
                $$index += scalar @target;
                return;
                };
            };

        if ($tokens->[$$index] eq "\n")
            {
            $$lineNumber++;
            $$index++;
            }
        else
            {
            $$index++;
            };
        };
    };


#
#   Function: IsFirstLineToken
#
#   Returns whether the position is at the first token of a line, not including whitespace.
#
#   Parameters:
#
#       index - The index of the position.
#
sub IsFirstLineToken #(index)
    {
    my ($self, $index) = @_;
    my $tokens = $self->Tokens();

    if ($index == 0)
        {  return 1;  };

    $index--;

    if ($tokens->[$index] =~ /^[ \t]/)
        {  $index--;  };

    if ($index <= 0 || $tokens->[$index] eq "\n")
        {  return 1;  }
    else
        {  return undef;  };
    };


#
#   Function: IsLastLineToken
#
#   Returns whether the position is at the last token of a line, not including whitespace.
#
#   Parameters:
#
#       index - The index of the position.
#
sub IsLastLineToken #(index)
    {
    my ($self, $index) = @_;
    my $tokens = $self->Tokens();

    do
        {  $index++;  }
    while ($index < scalar @$tokens && $tokens->[$index] =~ /^[ \t]/);

    if ($index >= scalar @$tokens || $tokens->[$index] eq "\n")
        {  return 1;  }
    else
        {  return undef;  };
    };


#
#   Function: IsAtSequence
#
#   Returns whether the position is at a sequence of tokens.
#
#   Parameters:
#
#       index - The index of the position.
#       token - A token to match.  Specify multiple times to specify the sequence.
#
sub IsAtSequence #(index, token, token, token ...)
    {
    my ($self, $index, @target) = @_;
    my $tokens = $self->Tokens();

    if ($index + scalar @target > scalar @$tokens)
        {  return undef;  };

    for (my $i = 0; $i < scalar @target; $i++)
        {
        if ($tokens->[$index + $i] ne $target[$i])
            {  return undef;  };
        };

    return 1;
    };


#
#   Function: IsBackslashed
#
#   Returns whether the position is after a backslash.
#
#   Parameters:
#
#       index - The index of the postition.
#
sub IsBackslashed #(index)
    {
    my ($self, $index) = @_;
    my $tokens = $self->Tokens();

    if ($index > 0 && $tokens->[$index - 1] eq "\\")
        {  return 1;  }
    else
        {  return undef;  };
    };



###############################################################################
#
#   Group: Scope Functions
#
#   These functions provide a nice scope stack implementation for language-specific parsers to use.  The default implementation
#   makes the following assumptions.
#
#   - Packages completely replace one another, rather than concatenating.  You need to concatenate manually if that's the
#     behavior.
#
#   - Packages inherit, so if a scope level doesn't set its own, the package is the same as the parent scope's.
#


#
#   Function: ClearScopeStack
#
#   Clears the scope stack for a new file.  Not necessary if you call <ParseForCommentsAndTokens()>.
#
sub ClearScopeStack
    {
    my ($self) = @_;
    $self->[SCOPE_STACK] = [ NaturalDocs::Languages::Advanced::Scope->New(undef, undef) ];
    $self->[SCOPE_RECORD] = [ NaturalDocs::Languages::Advanced::ScopeChange->New(undef, 1) ];
    };


#
#   Function: StartScope
#
#   Records a new scope level.
#
#   Parameters:
#
#       closingSymbol - The closing symbol of the scope.
#       lineNumber - The line number where the scope begins.
#       package - The package <SymbolString> of the scope.  Undef means no change.
#
sub StartScope #(closingSymbol, lineNumber, package)
    {
    my ($self, $closingSymbol, $lineNumber, $package) = @_;

    push @{$self->[SCOPE_STACK]},
            NaturalDocs::Languages::Advanced::Scope->New($closingSymbol, $package, $self->CurrentUsing());

    $self->AddToScopeRecord($self->CurrentScope(), $lineNumber);
    };


#
#   Function: EndScope
#
#   Records the end of the current scope level.  Note that this is blind; you need to manually check <ClosingScopeSymbol()> if
#   you need to determine if it is correct to do so.
#
#   Parameters:
#
#       lineNumber - The line number where the scope ends.
#
sub EndScope #(lineNumber)
    {
    my ($self, $lineNumber) = @_;

    if (scalar @{$self->[SCOPE_STACK]} > 1)
        {  pop @{$self->[SCOPE_STACK]};  };

    $self->AddToScopeRecord($self->CurrentScope(), $lineNumber);
    };


#
#   Function: ClosingScopeSymbol
#
#   Returns the symbol that ends the current scope level, or undef if we are at the top level.
#
sub ClosingScopeSymbol
    {
    my ($self) = @_;
    return $self->[SCOPE_STACK]->[-1]->ClosingSymbol();
    };


#
#   Function: CurrentScope
#
#   Returns the current calculated scope, or undef if global.  The default implementation just returns <CurrentPackage()>.  This
#   is a separate function because C++ may need to track namespaces and classes separately, and so the current scope would
#   be a concatenation of them.
#
sub CurrentScope
    {
    return $_[0]->CurrentPackage();
    };


#
#   Function: CurrentPackage
#
#   Returns the current calculated package or class, or undef if none.
#
sub CurrentPackage
    {
    my ($self) = @_;

    my $package;

    for (my $index = scalar @{$self->[SCOPE_STACK]} - 1; $index >= 0 && !defined $package; $index--)
        {
        $package = $self->[SCOPE_STACK]->[$index]->Package();
        };

    return $package;
    };


#
#   Function: SetPackage
#
#   Sets the package for the current scope level.
#
#   Parameters:
#
#       package - The new package <SymbolString>.
#       lineNumber - The line number the new package starts on.
#
sub SetPackage #(package, lineNumber)
    {
    my ($self, $package, $lineNumber) = @_;
    $self->[SCOPE_STACK]->[-1]->SetPackage($package);

    $self->AddToScopeRecord($self->CurrentScope(), $lineNumber);
    };


#
#   Function: CurrentUsing
#
#   Returns the current calculated arrayref of <SymbolStrings> from Using statements, or undef if none.
#
sub CurrentUsing
    {
    my ($self) = @_;
    return $self->[SCOPE_STACK]->[-1]->Using();
    };


#
#   Function: AddUsing
#
#   Adds a Using <SymbolString> to the current scope.
#
sub AddUsing #(using)
    {
    my ($self, $using) = @_;
    $self->[SCOPE_STACK]->[-1]->AddUsing($using);
    };



###############################################################################
# Group: Support Functions


#
#   Function: AddToScopeRecord
#
#   Adds a change to the scope record, condensing unnecessary entries.
#
#   Parameters:
#
#       newScope - What the scope <SymbolString> changed to.
#       lineNumber - Where the scope changed.
#
sub AddToScopeRecord #(newScope, lineNumber)
    {
    my ($self, $scope, $lineNumber) = @_;
    my $scopeRecord = $self->ScopeRecord();

    if ($scope ne $scopeRecord->[-1]->Scope())
        {
        if ($scopeRecord->[-1]->LineNumber() == $lineNumber)
            {  $scopeRecord->[-1]->SetScope($scope);  }
        else
            {  push @$scopeRecord, NaturalDocs::Languages::Advanced::ScopeChange->New($scope, $lineNumber);  };
        };
    };


#
#   Function: CreateString
#
#   Converts the specified tokens into a string and returns it.
#
#   Parameters:
#
#       startIndex - The starting index to convert.
#       endIndex - The ending index, which is *not inclusive*.
#
#   Returns:
#
#       The string.
#
sub CreateString #(startIndex, endIndex)
    {
    my ($self, $startIndex, $endIndex) = @_;
    my $tokens = $self->Tokens();

    my $string;

    while ($startIndex < $endIndex && $startIndex < scalar @$tokens)
        {
        $string .= $tokens->[$startIndex];
        $startIndex++;
        };

    return $string;
    };


1;
