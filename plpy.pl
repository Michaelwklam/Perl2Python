#!/usr/bin/perl -w

# written by Michael September 2016


sub translate {

    my ($indent) = @_;

    # <--------- Preprocess most syntax first ---------------------->
    $scriptToTranslate[0] = prepareSyntax();
    my $line = $scriptToTranslate[0]; 

    # <--------- Handle specific cases using subroutines ----------->
    
    if ($line =~ /^#!.*?perl/) {                          # header line
        return getHeader();
    } elsif ($line =~ /^\s*\$\$/) {                       # Lines marked by our syntax switcher
        $line = shift @scriptToTranslate;
        $line =~ s/\$\$//;
        return $line;
    } elsif ($line =~ /^\s*\$\w*/) {                      # Variable Declarations
        return translate_VarDec($indent);
    } elsif ($line =~ /^\s*$/) {                          # Empty Line
        shift @scriptToTranslate;
        return "\n";
    } elsif ($line =~ /^\s*print[^f].*$/) {               # Normal prints 
        return translate_Print($indent);
    }  elsif ($line =~ /^\s*printf.*$/) {                 # Printfs 
        return translate_Printf($indent);
    } elsif ($line =~ /^\s*if/) {                         # If
        return translate_If($indent);
    } elsif ($line =~ /\;\s*if\s*\(/) {                   # Special If, created by regexp usage
        return translate_If($indent);
    } elsif ($line =~ /^\s*[}]?\s*elsif/) {               # elsif
        return translate_elsif($indent);
    } elsif ($line =~ /^\s*[}]?\s*else/) {                # else
        return translate_else($indent);
    } elsif ($line =~ /^\s*while/) {                      # While
        return translate_While($indent);
    } elsif ($line =~ /^\s*foreach/) {                    # Foreach
        return translate_Foreach($indent);
    } elsif ($line =~ /^\s*for/) {                        # For
        return translate_For($indent);
    } elsif ($line =~ /^\s*open/) {                       # Open
        return translate_Open($indent);
    } elsif ($line =~ /^\s*sub/) {                        # Functions/Subs
        return translate_Sub($indent);
    } elsif ($line =~ /^\s*#/) {                          # Comments
        $line = shift @scriptToTranslate;
        return $line;
    } else {                                              # Not supported stuff
        $line = shift @scriptToTranslate;
        return "#".$line;
    }
}

sub prepareSyntax {

    # do not handle
    return $scriptToTranslate[0] if ($scriptToTranslate[0] =~ /^\s*sub/);
    
    # <------- preparatory conversions ----------->
    if ($scriptToTranslate[0] !~ /^\s*#/ && $scriptToTranslate[0] !~ /^\s*$/) {
        # restructure If statements written after dos
        if ($scriptToTranslate[0] =~ /^.*?\sif\s*\(?.*?\)?\s*;/) {
            $scriptToTranslate[0] = restructure_If($scriptToTranslate[0]);
        }

        # don't interpolate print strings, translateprint will do it automatically
        if ($scriptToTranslate[0] !~ /^\s*print.*$/ && $scriptToTranslate[0] =~ /\".*?\"/) {
            $scriptToTranslate[0] = var_interpolate($scriptToTranslate[0]);
        }  
       
        # look for anonymous variables
        $scriptToTranslate[0] = find_defaultVar($scriptToTranslate[0]);

        # do most syntax switching
        $scriptToTranslate[0] = convert_syntax($scriptToTranslate[0]); 
    }
    
    return $scriptToTranslate[0];

}

sub translate_For {
    # convert for loop into while loop
    my ($indent) = @_;
    my @python = ();
    my $line = shift @scriptToTranslate;
    my ($init, $test, $step) = $line =~ /\s*for\s*\((.*?)\;\s*(.*?)\;\s(.*?)\s*\)/ or die; 
    $test = convertObj($test);
    
    #put back the for loop as a while loop
    unshift @scriptToTranslate, "while ($test) {\n";
    unshift @scriptToTranslate, $init."\n";
    
    # add increment to the end of whileloop
    my $i;
    for ($i = 0; $i < $#scriptToTranslate; $i++) {
        last if ($scriptToTranslate[$i] =~ /}/);
    }
    splice @scriptToTranslate, $i, 0, "$step\n";
    
    return translate($indent);
}

sub translate_Foreach {
    my ($indent) = @_;
    my @python = ();
    my $line = shift @scriptToTranslate;
    
    if ($line =~ /\s*foreach\s*(\$[\w\d]+)\s*\((.*)\)/) {
        my ($arg, $list) = $line =~ /\s*foreach\s*(\$[\w\d]+)\s*\((.*)\)/ or die;         
        $arg = convertObj($arg);
        $list = convertObj($list);   
        $line = "for $arg in $list:\n";
    } elsif ($line =~ /\s*foreach\s*\$(\w*)\s*(range\(.*?\))/) {
        my ($arg, $range) = $line =~ /\s*foreach\s*\$(\w*)\s*(range.*?)\s*[{]$/ or die;
        $arg = convertObj($arg);
        $line = "for $arg in $range:\n";
    }
    
    push @python, (" " x $indent).$line;
    while (@scriptToTranslate && $scriptToTranslate[0] !~ /^\s*}/) {
        # push everything in the if statement with 4 indent
        push @python, translate($indent + 4);
    }

    # remove closing squiggly
    $scriptToTranslate[0] =~ s/}//;
    
    return @python;
}

sub translate_While {
    my ($indent) = @_;
    my @python = ();
    my $line = shift @scriptToTranslate;
    my ($condition) = $line =~ /\s*while\s*\((.*)\)/ or die;
    $condition = convertObj($condition);

    # check if we need to translate any operators in condition
    $condition = convertOperators($condition);
    
    # special conditions, while (<>)
    if ($condition =~ /(\w*)\s*=\s*sys.stdin.readline/) {
        # convert into for loop
        my $var = $1;
        addImport('fileinput');
        $line =~ s/while\s*\(.*\)\s*{/for $var in fileinput.input():/;
    } elsif ($condition =~ /(\w*)\s*=\s*sys.stdin/) {
        my $var = $1;
        addImport('sys');
        $line =~ s/while\s*\(.*\)\s*{/for $var in sys.stdin:/;
    } else {
        $line =~ s/while\s*\(.*\)\s*{/while $condition:/;
    }
    
    push @python, $line;

    while (@scriptToTranslate && $scriptToTranslate[0] !~ /^\s*}/) {
        # push everything in the if statement with 4 indent
        push @python, translate($indent + 4);
    }
    #remove closing squiggly
    $scriptToTranslate[0] =~ s/}//;

    return @python;
}  

sub translate_If {

    my ($indent) = @_;
    my @python = ();
    my $line = shift @scriptToTranslate;

    #for special ifs made by regex usage
    if ($line =~ /(;\s*)if\s*\(/) {
        my @lines = split /$1/, $line;
        my $regexLine = shift @lines;
        $regexLine .= "\n";
        push @python, (" " x $indent).$regexLine; 
        $line = shift @lines;      
    }

    my ($condition) = $line =~ /\s*if\s*\((.*)\)/ or die;

    $condition = convertObj($condition);

    # check if we need to translate any operators in condition
    $condition = convertOperators($condition);

    $line =~ s/\s*if\s*\(.*\)\s*{/if $condition:/;
    push @python, (" " x $indent).$line;

    while (@scriptToTranslate && $scriptToTranslate[0] !~ /^\s*}/) {
        # push everything in the if statement with 4 indent
        push @python, translate($indent + 4);
    }
    #remove closing squiggly
    $scriptToTranslate[0] =~ s/}//;

    return @python;
}

sub translate_elsif {

    my ($indent) = @_;
    my @python = ();
    my $line = shift @scriptToTranslate;
    my ($condition) = $line =~ /\s*[}]?\s*elsif\s*\((.*)\)/ or die;
    $condition = convertObj($condition);

    # check if we need to translate any operators in condition
    $condition = convertOperators($condition);

    $line =~ s/\s*[}]?\s*elsif\s*\(.*\)\s*{/elif $condition:/;
    push @python, (" " x $indent).$line;

    while (@scriptToTranslate && $scriptToTranslate[0] !~ /^\s*}/) {
        # push everything in the if statement with 4 indent
        push @python, translate($indent + 4);
    }
    #remove closing squiggly
    $scriptToTranslate[0] =~ s/\s*}$//;
    return @python;
}

sub translate_else {

    my ($indent) = @_;
    my @python = ();
    my $line = shift @scriptToTranslate;
    
    $line =~ s/\s*[}]?\s*else\s*[{]/else:/;
    push @python, (" " x $indent).$line;

    while (@scriptToTranslate && $scriptToTranslate[0] !~ /^\s*}/) {
        # push everything in the if statement with 4 indent
        push @python, translate($indent + 4);
    }
    #remove closing squiggly
    $scriptToTranslate[0] =~ s/\s*}$//;
    return @python;
}

sub translate_Print {
    my ($indent) = @_;
    my $line = shift @scriptToTranslate;
    my @python = ();
    my @vars = ();    
    my $noNewLine = 1;
    my $inVar = 0;
    my $inList = 0;

    #convert all ' to "
    $line =~ s/\'(.*?)\'/\"$1\"/g;
      
    # make sure our print has a ; behind or ggwp script ded
    if ($line !~ /;\s*$/) {     
        chomp $line;
        $line =~ s/\s*$//;
        $line = $line.";\n";
    }
    
    # remove newline separated from variables in print
    my $replacements = $line =~ s/,\s*"\s*\\n\s*"//;
    $noNewLine = 0 if ($replacements);
    
    # remove print
    $line =~ s/\s*(print)\s*//g;
    push @python, (" " x $indent).$1;
    
    # in python 3, print is now a function so we need brackets
    push @python, "(";
    
    # split line into chars
    my @chars = split("", $line);
    my @string = ();

    while (@chars) {
        my $char = shift @chars;

        # handle quoted strings
        if ($char eq "\"") {
            do {{
                $char = shift @chars;
    
                # if it's a newline we're gonna ignore it
                if ($char eq "\\") {
                    $char = shift @chars;
                    if ($char eq 'n') {
                        $noNewLine = 0;
                        next;
                    }
                    $char = '\\'.$char;
                }

                # variable inside the quotes
                if ($char eq "\$") {
                    # get the variable name
                    if (@vars) {
                        push @vars, ",";
                    } else {
                        push @vars, " % (";
                    }
                    
                    do {
                        $char = shift @chars;
                        push @vars, $char if ($char =~ /\w/ || $char =~ /[\[\]{}]/);   
                    } until ($char =~ /[^\w]/ && $char !~ /[\[\]{}]/);
                    
                    #for hashes and arrays, continue
                    if ($char eq "\$") {
                        do {
                            $char = shift @chars;
                            push @vars, $char if ($char =~ /\w/ || $char =~ /[\[\]{}]/);   
                        } until ($char =~ /[^\w]/ && $char !~ /[\[\]{}]/);
                    }
                    
                    #put back whatever is inside
                    unshift @chars, $char;
                    
                    $char = "%s";
                }
                
                # list inside the quotes
                if ($char eq "\@") {
                    # get the variable name
                    if (@vars) {
                        push @vars, ",";
                    } else {
                        push @vars, " % (";
                    }
                    push @vars, "''.join(";

                    do {
                        $char = shift @chars;
                        push @vars, $char if ($char =~ /\w/ || $char =~ /[\[\]{}]/);   
                    } until ($char =~ /[^\w]/ && $char !~ /[\[\]{}]/);

                    push @vars, ")";

                    #put back whatever is inside
                    
                    unshift @chars, $char;
                    $char = "%s";
                }

                push @string, $char if ($char ne "\"");
            }} until ($char eq "\"");
        } else {
            # if not in quotes, everything will be considered a variable
            if ($char eq "\$" || $char eq "\@") {
                $inVar = 1;
                push @string, "%s";
                 if (@vars) {
                    push @vars, ",";
                } else {
                    push @vars, " % (";
                }
            } 
            $inList = 1 if ($char eq "\@");

            if ($inVar) {
              
                push @vars, "''.join(" if ($inList);

                while (@chars && $char ne ";" && $char ne "+") {
                    push @vars, $char if ($char ne "\$" && $char ne ";" && $char ne "\@");
                    $char = shift @chars;
                    last if ($char eq ";" || $char eq "+");
                }
                # if char is + we want to check if the next char is a quote, else push it as well
                if ($char eq "+") {
                    my $i;
                    for ($i = 0; $i < $#chars; $i++) {
                        last if ($chars[$i] ne " ");
                    }
                    push @vars, $char if ($chars[$i] =~ /\d/);
                }
                $inVar = 0;
                if ($inList) {
                    push @vars, ")";
                }
            }
        }     
    }

    # close our variables
    push @vars, ")" if (@vars);

    # push string into output
    my $finalString = "\"".join('',@string)."\"";
    push @python, $finalString;

    # push our vars 
    push @python, @vars if (@vars);

    #if user didn't put in newline
    push @python, ", end=''" if ($noNewLine);

    #close brackets for python print
    push @python, ")\n";
    
    return @python;
}

sub translate_Printf {
    my ($indent) = @_;
    my $line = shift @scriptToTranslate;
    my @python = ();
    my $noNewLine = 1;
     
    # remove newline separated from variables in print
    my $replacements = $line =~ s/,\s*"\s*\\n\s*"//;
    $noNewLine = 0 if ($replacements);

    if ($line =~ /\\n\s*"/) {
        $line =~ s/\\n\s*"/"/;
        $noNewLine = 0;
    }

    my ($quotedSegment) = $line =~ /(".*?")/;
    my ($varSegment) = $line =~ /".*?"\s*,\s*(.*?)\s*;/;

    my @formatAnchors = $quotedSegment =~ /(%[^ ]*)/g;
    my @formatVars = split /,/, $varSegment;

    foreach (@formatVars) {
        $_ = convertObj($_);
    }

    my @stringVars = ($quotedSegment =~ /\$(\w*)/g);

    foreach my $varInString (@stringVars) {
        #match how many formats before this variable by chopping off everything
        (my $tempString = $quotedSegment) =~ s/\$$varInString.*//;
        my @matches = ($tempString =~ /(%[^ ]*)/g);       
        $quotedSegment =~ s/\$$varInString/\%s/;
        splice @formatVars, $#matches+1, 0, $varInString;
    } 
    my $finalVars = join(",", @formatVars);
    #push our final line into the return python
    push @python,  (" " x $indent);
    push @python, "print($quotedSegment % ($finalVars)";

    #if user didn't put in newline
    push @python, ", end=''" if ($noNewLine);

    #close brackets for python print
    push @python, ")\n";

    return @python;
}

sub translate_VarDec {
    
    my ($indent) = @_;
    my $line = shift @scriptToTranslate;
    my @python = ();
    $line = convertObj($line);
    $line =~ s/^\s*// if ($indent > 0);
    $line = stripSemicolon($line);
    push @python, (" " x $indent).$line;
    return @python;
}

sub restructure_If {
    my ($line) = @_;
    my @newIf = ();
    $line =~ /^(\s*)(.*?)(if\s*\(?.*?\)?\s*);/ or die;
    my $indent = $1;
    my $statement = $2;
    my $if = $3;
    if ($if !~ /if\s*\(.*?\)/) {
        $if =~ s/if\s*(.*)/if \($1\)/;
    }
    push @newIf, $indent.$if." {\n";
    push @newIf, $indent.(" " x 4).$statement."\n";
    push @newIf, $indent."}\n";
    shift @scriptToTranslate;
    unshift @scriptToTranslate, @newIf;
    
    return $scriptToTranslate[0];
}

sub getHeader {
    my $line = shift @scriptToTranslate;
    my @header = ("#!/usr/local/bin/python3.5 -u\n");
    #my @header = ("#!/usr/bin/python3.5 -u\n");
    return @header;
} 

sub stripSemicolon {
    my ($line) = @_; 
    $line =~ s/\s*;\s*$/\n/;
    return $line;
}

sub addImport {
    my ($library) = @_;
    
    if ($outputScript[$importLine] =~ /\s*import\s*(.*)/) {
        if ($1 !~ /$library/) {
            $outputScript[$importLine] =~ s/\n//;
            $outputScript[$importLine].=",".$library."\n";
        }   
    } else {
        splice @outputScript, $importLine, 0, "import $library\n";
    }
}

sub translate_Open {
    my ($indent) = @_;
    my $line = shift @scriptToTranslate;
    my ($filehandle, $expr, $file) = $line =~ /open\s*\(?\s*(\w*)\s*,\s*"\s*(\W?)(.*?)"\)?/;
    my $permissions;
 
    if ($expr eq "<") { #r Readonly access
        $permissions = "r";
    } elsif ($expr eq ">") { #w Create/Write/Truncate
        $permissions = "w";
    } elsif ($expr eq "+>") { #w+ Read/write/create/truncate
        $permissions = "w+";
    } elsif ($expr eq "+<") { #r+ read/write
        $permissions = "r+";
    } elsif ($expr eq ">>") { #a write/append/create
        $permissions = "a";
    } elsif ($expr eq "+>>") { #a+ read/write/append/create
        $permissions = "a+";
    }
    if ($file) {
        $line =~ s/open.*/$filehandle = open("$file", "$permissions")/;
    } else {
        $line =~ s/open.*/$filehandle = open($filehandle, "$permissions")/;
    }


    #modify lines afterwards
    foreach my $i (0.. $#scriptToTranslate) {
        #convert while loops to foreach
        if ($scriptToTranslate[$i] =~ /while\s*\(\s*(\$\w*)\s*=\s*<\s*$filehandle\s*>\s*\)/) {
            my $newLine = "foreach $1 ($filehandle)";
            $scriptToTranslate[$i] =~ s/while\s*\(.*?\)/$newLine/;
        }
        if ($scriptToTranslate[$i] =~ /^\s*close.*?$filehandle/) {
            # put $$ only tell our handler we have modified line already
            $scriptToTranslate[$i] =~ s/close.*/\$\$$filehandle.close()/;
            last;
        }
    }

    return $line;
}

sub translate_Sub {
    my ($indent) = @_;
    my $line = shift @scriptToTranslate;
    my ($fnName) = $line =~ /sub\s*(.*?)\s*{/;
    my $params;
    my @python;
    chomp $line;
    
    #store the sub name somewhere so we know what to do in future
    push @customFunctions, $fnName;

    # first change the sub to def
    $line =~ s/sub/def/;

    # add bracket for parameters
    $line =~ s/$fnName.*/$fnName(/;
    
    
    #look for parameters (assume it's on the next 5 lines)
    foreach my $i (0..4) {
        if ($scriptToTranslate[$i] =~ /(my)?\s*\(+(.*?)\)+\s*=\s*\@_/) {
            $params = $2;
            splice @scriptToTranslate, $i, 1;
            last;
        } 
    }

    if ($params) {
        $params = convertObj($params);
        $line .= $params;
    }
    $line .= "):\n";

    push @python, $line;

    while (@scriptToTranslate && $scriptToTranslate[0] !~ /^\s*}/) {
        # push everything in the if statement with 4 indent
        push @python, translate($indent + 4);
    }

    #remove closing squiggly
    $scriptToTranslate[0] =~ s/\s*}$//;
    
    return @python;
}

sub convertObj {
    my ($line) = @_;
    
    # check if there's an ARGV inside
    if ($line =~ /^[^"]*\@ARGV/) {
        addImport('sys');
        $line =~ s/\@ARGV/sys.argv[1:]/g;
    }

    my $inString = 0;
    my @finalLine = ();
    my @chars = split("", $line);
    my $backSlashed = 0;

    while (@chars) {
        my $char = shift @chars;
        my $nextChar = $chars[0] if (@chars);

        if ($char eq "\"") {
            $inString = $inString ? 0 : 1;
        } elsif ($char eq "\$" && !$inString && !$backSlashed && $nextChar !~ /\d/) {
            #skip
            do {
                $char = shift @chars;
            } until ($char ne "\$");
        } elsif ($char eq "\@" && !$inString) {
            #skip
            do {
                $char = shift @chars;
            } until ($char ne "\@");
        }

        push @finalLine, $char;  
        $backSlashed = ($char eq "\\") ? 1 : 0;
    }
 
    return join('', @finalLine);
}

sub convertFnParam {
    my ($line) = @_;
    
    my ($params) = $line =~ /\((.*)\)/; 
    my @params = split ',',$params;

    foreach $param (@params) {
        if ($param !~ /^\".*?\"$/) {
            $param =~ s/\$//g;
            $param =~ s/\@//g;
        }
    }
    
    my $convertedParams = join",", @params;
    $params =~ s/\$/\\\$/g;
    $line =~ s/$params/$convertedParams/;
    
    return $line;
}

sub convertOperators {
    
    my ($line) = @_;
    #process line char by char - in case operator is part of a string
    my $inString = 0;
    my @python = ();
    my $toPush;
    my @chars = split("", $line);
    my $isSpaceBefore;
    my $isSpaceAfter;

    while (@chars) {
        my $char = shift @chars;
        my $nextChar = $chars[0] if (@chars);

        #can't read for the last 2 characters
        if ($chars[1]) {
            $isSpaceAfter = ($chars[1] eq " ") ? 1 : 0;
        } else {
            $isSpaceAfter = 0;
        }
        $toPush = $char;

        if ($char eq "\"") {
            $inString = $inString ? 0 : 1;
        } elsif ($char eq "l" && !$inString && $isSpaceAfter && $isSpaceBefore) {# lt & le
            if ($nextChar eq "t") {
                $toPush = "<";
            } elsif ($nextChar eq "e") {
                $toPush = "<=";
            }
        } elsif ($char eq "g" && !$inString && $isSpaceAfter && $isSpaceBefore) {# gt & ge
            if ($nextChar eq "t") {
                $toPush = ">";
            } elsif ($nextChar eq "e") {
                $toPush = ">=";
            }
        } elsif ($char eq "e" && !$inString && $isSpaceAfter && $isSpaceBefore) {# eq
            if ($nextChar eq "q") {
                $toPush = "==";
            }
        } elsif ($char eq "n" && !$inString && $isSpaceAfter && $isSpaceBefore) {# ne
            if ($nextChar eq "e") {
                $toPush = "!=";
            }
        } elsif ($char eq "&" && !$inString) {                                   # &&
            if ($nextChar eq "&") {
                $toPush = "and";
            }
        } elsif ($char eq "|" && !$inString) {                                   # ||
            if ($nextChar eq "|") {
                $toPush = "or";
            }
        } elsif ($char eq "!" && !$inString) {                                   # !
            if ($nextChar ne "=") {
                $toPush = "not ";
                $char = $toPush;
            }           
        } 

        shift @chars if ($toPush ne $char);
        push @python, $toPush;  
        $isSpaceBefore = ($char eq " ") ? 1 : 0;
    }
    
    return join('', @python);
}

# Preprocessors - for simple syntax switching

sub convert_syntax {
    my ($line) = @_;
    
    # quick die translator that is not required
    if ($line =~ /die\s*[\"'](.*?)[\"']/) {
        addImport('sys');
        $line =~ s/die.*/\$\$sys.exit()/;
        return $line;
    } 

    # variable scoping
    if ($line =~ /\s*my\s*[\$\@]\w*\s*/) {
        #we can trim off my, python is already scoped correctly
        $line =~ s/my\s*//;       
    }

    # inc and dec
    if ($line =~ /(\$\w*[{\[.*?\]}]?)\s*[\+-]{2}/) {
        $line =~ s/(\$\w*[{\[.*?\]}]?)\s*\+\+/$1 \+= 1/g;
        $line =~ s/(\$\w*[{\[.*?\]}]?)\s*--/$1 -= 1/g;
    }
    
    #returns
    if ($line =~ /^\s*return.*/) { 
        $line = convertObj($line);
        $line = stripSemicolon($line);
        #mark as handled
        $line = "\$\$".$line;
    }

    # array indexing
    if ($line =~ /\$#(\w*)/) {
        
        my $list = $1;
        if ($list eq "ARGV") {
            $list = "sys.argv";
            addImport('sys');
        } 
        $line =~ s/\$#(\w*)/len\($list\) - 1/g;
    }
   
    if ($line =~ /\$(\w*)\[(.*?)\]/ ){
        my $array = $1;
        my $arrayIndex = $2;

        #interpolate the line in case it's wrapped in quotes
        $line = var_interpolate($line);
       
        if ($array eq "ARGV") {
            $array = "\$sys.argv";
            addImport('sys');
            if ($arrayIndex =~ /\$.*/) {
                $array = $array."[$arrayIndex + 1]";
            } else {
                $arrayIndex += 1;
                $array = $array."[$arrayIndex]";
            }
            
        } else {
            $arrayIndex =~ s/\$//g;
            $array = "\$".$array."[$arrayIndex]";
        }
        # else it doesn't matter, convertObj will handle it later
        $line =~ s/\$(\w*)\[(.*?)\]/$array/g;
    }
    
    # glob
    if ($line =~ /glob\s*(['"].*?['"])/) {
        $line =~ s/glob\s*(['"].*?['"])/glob.glob($1)/;
        addImport('glob');
    }

    #lowercase, uppercase
    if ($line =~ /lc\s*\(?(\$[\w\.\[\]]*)\)?/) {
        $line =~ s/lc\s*\(?(\$[\w\.\[\]]*)\)?/$1.lower()/;
    }
    if ($line =~ /uc\s*\(?(\$[\w\.\[\]]*)\)?/) {
        $line =~ s/uc\s*\(?(\$[\w\.\[\]]*)\)?/$1.upper()/;
    }

    # next, last, exit
    if ($line =~ /^\s*last\s*[;]?/) {
        $line =~ s/last/\$\$break/;
    }

    if ($line =~ /^\s*next\s*[;]?/) {
        $line =~ s/next/\$\$continue/;
    }

    if ($line =~ /^\s*exit\s*[;]?/) {
        $line =~ /exit\s*(\d*)?/;
        use Scalar::Util qw(looks_like_number);

        my $exitStat = $1;     
        if (looks_like_number($exitStat)) {
            addImport('sys');
            $line =~ s/exit\s*\d*/\$\$sys.exit($exitStat)/;
        } else {
            addImport('sys');
            $line =~ s/exit/\$\$sys.exit()/;
        }
    }

    # ranges
    if ($line =~ /\(\s*\d\.\.\d\s*\)/) {
        $line =~ /(\d)\.\.(\d)/ or die;
        my $r1 = $1;
        my $r2 = $2+1;
        if ($r1 != 0) {
            $line =~ s/(\d)\.\.(\d)/range($r1, $r2)/;
        } else {
            $line =~ s/(\d)\.\.(\d)/range($r2)/;
        }
        
    } elsif ($line =~ /\(\s*.*\.\..*\s*\)/) {
        $line =~ /\(\s*(.*?)\.\.(.*)\s*\)/ or die;
        my $r1 = $1;
        my $r2 = $2;
        
        if ($r1 != 0) {
            $line =~ s/\(\s*(.*?)\.\.(.*)\s*\)/range($r1, $r2)/;
        } else {
            $line =~ s/\(\s*(.*?)\.\.(.*)\s*\)/range($r2)/;
        }
    }
    
    # <--- concats --->
    # Supported: $a.$b."abc".'abc'
    # Checks if it's actually a string - in a string you'd have to use \ to ignore $ sign
    if ($line =~ /([^\\]\$\w*|[\"\'].*?[\"\'])\s*\.\s*([^\\]\$\w*|[\"\'].*?[\"\'])/) {      
        while ($line =~ /(\$\w*|[\"\'].*?[\"\'])\s*\.\s*(\$\w*|[\"\'].*?[\"\'])/) {
            $line =~ s/(\$\w*|[\"\'].*?[\"\'])\s*\.\s*(\$\w*|[\"\'].*?[\"\'])/$1 + $2/;   
        }       
    }
    
    #.=
    if ($line =~ /^\s*(\$\w*)\s*\.=\s*(.*)/) {
        my $r1 = $1;
        my $r2 = $2;
        $line =~ s/\.=.*/= $r1 + $r2/;
    }

    # regexp usage
    # substitute
    if ($line =~ /^(\s*)(\$\w*)\s*=~\s*s\/(.*?)\/(.*?)\/(g)?/) {
        addImport('re');
        if ($5 && $5 eq 'g') {
            $line = "$1$2 = re.sub(r'$3','$4',$2)\n";
        } else {
            $line = "$1$2 = re.sub(r'$3','$4',$2, count=1)\n";
        }      
    }

    # match
    if ($line =~ /if\s*\(\s*\$(\w*)\s*=~\s*\/(.*?)\/(\w)?\s*\)/) {
        my $sub;
        addImport('re');
        if ($3 && $3 eq 'i') {
           $sub = "my_M = re.match(r'$2',$1, re.IGNORECASE);";
        }else {
           $sub = "my_M = re.match(r'$2',$1);";
        }  
        
        $line =~ s/(\$\w*)\s*=~\s*\/(.*?)\/(\w)?/\$my_M/; 
        $line = "$sub$line";

        # no more processing
        return $line;
    }
    
    # chomp
    if ($line =~ /chomp\s*\$(\w*)/) {
        die if (!$1);
        # add in $ in front so our vardec will process it
        my $replace = "\$"."$1 = $1.rstrip('\\n')";
        $line =~ s/chomp.*/$replace/;
    }
    
    # split
    if ($line =~ /split\(?.*\)?/) {
        my ($regexp, $var) = $line =~ /split\s*\(?\/(.*?)\/\s*,\s*(\$\w*)\)?/ or die;
        addImport('re');
        $var = convertObj($var);
        my $replace = "re.split(r'$regexp', $var)";

         #replace all if no bracket
        if ($line =~ /split\s*[^\(*]/) {
            $line =~ s/split.*?;/$replace/;
        } elsif ($line =~ /split\s*\(/) {
            #replace only partial if there's a bracket
            $line =~ s/split\s*\([^\)]*\)/$replace/;
        }
    }

    # push (variable)
    if ($line =~ /push\s*[\(]?\s*\@([\$]?\w*)\s*,\s*\$(\w*)\s*[\)]?/) {
        my $list = $1;
        my $append = $2;
        $line =~ s/push.*/\$\$$list.append($append)/;
    }
    # push (string)
    if ($line =~ /push\s*\@([\$]?\w*)\s*,\s*(["'].*?["'])/) {
        my $list = $1;
        my $append = $2;
        $line =~ s/push.*/\$\$$list.append($append)/;
    }
    # push (list)
    if ($line =~ /push\s*\@([\$]?\w*)\s*,\s*\@([\$]?\w*)/) {
        my $list = $1;
        my $append = $2;
        $line =~ s/push.*/\$\$$list.extend($append)/;
    }
    # pop
    if ($line =~ /pop\s*\@([\$]?\w*)\s*/) {
        my $list = $1;
        $line =~ s/pop\s*\@\w*/\$\$$list.pop()/;
    }
    # shift
    if ($line =~ /[^n]shift\s*\@([\$]?\w*)\s*/) {
        my $list = $1;
        $line =~ s/shift\s*\@\w*/\$\$$list.pop(0)/;
    }
    # unshift (variable)
    if ($line =~ /unshift\s*\@([\$]?\w*)\s*,\s*\$(\w*)/) {
        my $list = $1;
        my $append = $2;
        $line =~ s/push.*/\$\$$list.insert(0,$append)/;
    }
    # unshift (string)
    if ($line =~ /unshift\s*\@([\$]?\w*)\s*,\s*(["'].*?["'])/) {
        my $list = $1;
        my $append = $2;
        $line =~ s/unshift.*/\$\$$list.insert(0,$append)/;
    }
    # unshift (list)
    if ($line =~ /unshift\s*\@([\$]?\w*)\s*,\s*\@([\$]?\w*)/) {
        my $list = $1;
        my $append = $2;
        $line =~ s/unshift.*/\$\$$list\[0:0\] = $append/;
    }

    # reverse (list)
    if ($line =~ /reverse\s*\@(\w*)/) {
        my $list = $1;
        $line =~ s/reverse.*\@(\w*)/$1.reverse()/;
    }
   
    # join with brackets
    if ($line =~ /\sjoin\(?.*\)?/) {
        my $printMode = 0;
        my ($expr, $list) = $line =~ /join\s*\(?[\"\'](.*?)[\"\']\s*,\s*(\@?[\w|.]*(\(\))?)\)?/;
        
        $list = convertObj($list);
        my $replace = "'$expr'.join($list)";

        # check if the join is being used as a print
        $printMode = 1 if ($line =~ /print\s*join/);

        #replace all if no bracket
        if ($line =~ /join\s*[^\(*]/) {
            if (!$printMode) {
                $line =~ s/join.*?;/$replace/;
            } else {
                $line =~ s/join.*?;/\$$replace/;
            }
            
        } elsif ($line =~ /join\s*\(/) {
            #replace only partial if there's a bracket
            if (!$printMode) {
                $line =~ s/join\s*\(.*\)/$replace/;
            } else {
                $line =~ s/join\s*\(.*\)/\$$replace/;
            }
        } 
       
    }

    # <--- reads --->
    # stdin - <STDIN> or <>
    if ($line =~ /^\s*[\$|\@](\w*)\s*=\s*\<(.*)\>/) {
        if ($2 eq "STDIN") {
            my $varType = guessVarNature($1);
            addImport('sys');
            if ($varType eq "float") {
                $line =~ s/<\s*STDIN\s*>/float(sys.stdin.readline())/;
            } else {
                $line =~ s/<\s*STDIN\s*>/sys.stdin.readline()/;
            }    
        } elsif ($2 eq "") {
            my $varType = guessVarNature($1);
            addImport('sys');
            $line =~ s/<\s*>/sys.stdin.readline()/;
            if ($varType eq "float") {
                $line =~ s/<\s*STDIN\s*>/float(sys.stdin.readline())/;
            } else {
                $line =~ s/<\s*STDIN\s*>/sys.stdin.readline()/;
            }    
        }
    }

    # different in while loop
    if ($line =~ /^\s*while.*?\<(.*)\>/) {
        
        if ($1 eq "STDIN") {
            addImport('sys');
            $line =~ s/<\s*STDIN\s*>/sys.stdin/;
        } elsif ($1 eq "stdin") {
            addImport('sys');
            $line =~ s/<\s*stdin\s*>/sys.stdin/;
        } elsif ($1 eq "") {
            addImport('sys');
            $line =~ s/<\s*>/sys.stdin.readline()/;
        }
    }

    # <--- Arrays --->
    # argv 
    if ($line =~ /^[^"]*\@(\w*)[^"]*/) { 
        if ($1 eq "ARGV") {
            addImport('sys');
            $line =~ s/\@ARGV/sys.argv[1:]/g;
        }    
    }
    # array initialization
    if ($line =~ /^\s*\@(\w*)\s*=\s*(.*)/) {
        # trim @
        $line = convertObj($line);

        # we don't need to process if initilization is sys.stdin
        if ($2 !~ /sys.stdin/) {
            # array initialized in brackets
            if ($2 =~ /\(.*?\)/) {
                $line =~ s/\(/\[/;
                $line =~ s/\)/\]/;
            } elsif ($2 =~ /qw[\/\(](.*?)[\/\)]/) { #init with qw
                my @init = split / /, $1;
                my $newInit = join ',', map qq('$_'), @init;
                $line =~ s/qw[\/\(](.*?)[\/\)]/[$newInit]/;
            }
            # mark as handled
            $line = "\$\$".$line;
        }else {
            #mark as handled
            $line = "\$\$".$line;
        }
    } 

    if ($line =~ /^\s*\@(\w*)\s*;/) {
        
        $line = convertObj($line);
        $line =~ s/;/= []/;
        # mark as handled
        $line = "\$\$".$line;
    }

    # <--- Hashes --->
    while ($line =~ /(\$\w*)\s*{(.*?)}/) {
        my $hasharray = $1;
        my $hashKey = $2;       
        $hashKey = convertObj($hashKey) if ($hashKey !~ /\$\d*/);
        $line =~ s/(\$\w*)\s*{(.*?)}/$hasharray\[$hashKey\]/; 
        addHashInit($hasharray);
    }
    
    # put a bracket so foreach handler will handle it properly
    if ($line =~ /\(\s*sort\s*keys\s*%\w*\s*\)/) {
        $line =~ s/\(\s*sort\s*keys\s*%(\w*)\s*\)/(sorted($1.keys()))/;
    }
    
    # call hash inc/dec handler if it sees hash += 1
    if ($line =~ /\$\w*\[.*?\]\s*(\+=|-=)\s*\d*\s*;/) {
        $line = adjustHash_IncDec($line);
    }

    # check if user is using a declared subroutine
    foreach my $subs (@customFunctions) {
        if ($line =~ /^\s*$subs\s*\(.*\)/) {
            $line = convertFnParam($line);
            $line = "\$\$".$line;
        } elsif ($line =~ /\s*$subs\s*\(.*\)/) {
            $line = convertFnParam($line);
        }
    }
    return $line;
}

sub find_defaultVar {
    #doesn't handle all cases, just simple ones
    my ($line) = @_;

    # prints
    if ($line =~ /^\s*print\s*;/) {
        $line =~ s/print/print \$_/;
    }

    # regex usage
    # substitute
    if ($line =~ /^(\s*)s\/(.*?)\/(.*?)\/(\w*)?/) {
        addImport('re');
        my $indent = $1;
        my $regex = $2;
        my $sub = $3;
        my $flags = $4;
        if ($flags && $flags =~ /g/) {
            $line = "$1\$_ = re.sub(r'$regex','$sub',\$_)\n";
        } else {
            $line = "$1\$_ = re.sub(r'$regex','$sub', \$_, count=1)\n";
        }      
    }

    #empty while (<>)
    if ($line =~ /^\s*while\s*\(\s*<>\s*\)/) {
        $line =~ s/\(\s*<>\s*\)/\(\$_ = <>\)/;
    }
    return $line;
}

sub guessVarNature {
    # looks into the rest of the code to see how the variable will be used
    # to determine if we should wrap it in a cast
    my ($varname) = @_;
    my $i;
    my $numOcc = 0;
    my $stringOcc = 0;

    for ($i = 0; $i <= $#scriptToTranslate; $i++) {
        if ($scriptToTranslate[$i] =~ /\$$varname\s*[<%>==]\s*\d*/) {
            #chances are it's a number
            $numOcc++;
        } elsif ($scriptToTranslate[$i] =~ /\$$varname\s*\w{2}\s*['"].*?['"]/) {
            #chances are it's a string
            $stringOcc++;
        }
    }
    my $varType = ($numOcc > $stringOcc) ? "float" : "string";
    return $varType;
}

sub var_interpolate {

    my ($line) = @_;
    
    # make sure our line has a ; behind or ggwp script ded
    if ($line !~ /;\s*$/) {     
        chomp $line;
        $line = $line.";\n";
    }    
    
    my $inQuotes;
    # split line into chars
    my @chars = split("", $line);
    my $inString = 0;
    my @newLine = ();
    my $nextChar;

    while (@chars) {
        my $char = shift @chars;
        
        if (@newLine > 0) {
            # concat
            if (!$inString && $newLine[$#newline] eq "\"" && $char eq "\"") {
                push @newLine, "+";
            }
            
            #quoted variable found
            if ($inString && $char eq "\$" && $newLine[$#newline] ne "\\") {
                
                push @newLine, "\"+";
                do {
                    $nextChar = $chars[0];
                    push @newLine, $char; 
                    $char = shift @chars;
                } until ($char eq "\"" || $char eq " ");
                $inString = 0;
                if ($char eq " ") {
                    push @newLine, "+\"";
                    $inString = 1;
                }
                next if ($char eq "\"");
            }
        }
        
        push @newLine, $char; 

        if ($char eq "\"") {
            $inString = $inString ? 0 : 1;
        }    
    }

    $line = join('', @newLine);

    # undo any damage done
    # remove empty strings with concats
    $line =~ s/\"\"\+//g;
    $line =~ s/\+\"\"//g;
    # remove new lines after variables
    $line =~ s/(\$[^\\]*)\\n/$1\+"\\n"/g;
    # remove trailing concats
    $line =~ s/\+\s*[;]$//;
    # quick fix for empty strings being destroyed
    if ($line =~ /(\$\w*)\s*=\s*[;]/) {
        $line = $1."= \"\"\n";
    }
    
    $line = stripSemicolon($line);

    return $line;
}

sub getImportLine {
    foreach my $i (1.. $#scriptToTranslate) {
        return $i-1 if ($scriptToTranslate[$i] !~ /^\s*#.*/ && $scriptToTranslate[$i] !~ /^\s*$/ );
    }
}

sub adjustHash_IncDec {
    my ($line) = @_;
    my ($indent, $list, $hashKey) = $line =~ /(\s*)\$(\w*)\[(.*?)\]\s*\+=|-=\s*\d*/ or die;

    # stripSemicolon to prevent deep recursion
    $line = stripSemicolon($line);

    # remove the line
    shift @scriptToTranslate;

    # add hash key check while making it look like genuine syntax
    my @newLine = ("if ($hashKey in $list) {\n","$line","} else {\n","    \$$list\[$hashKey] = 1;\n","}\n");
    unshift @scriptToTranslate, @newLine;

    return $scriptToTranslate[0];
}

sub addHashInit {
    # this is assuming user is a normal person and not trying to break 
    # the damn script
    my ($hash) = @_;
    $hash = convertObj($hash);
    my $i;

    # first make sure hash was never initiliazed before
    for ($i = $#outputScript; $i > 0; $i--) {
        if ($outputScript[$i] =~ /^\s*$hash\s*=\s*{}/) {
            last;         
        }
    }
    
    if ($i == 0) {
        for ($i = $#outputScript; $i > $importLine; $i--) {
            last if ($outputScript[$i] =~ /^[^\s]/)
        }
        if ($outputScript[$i] !~ /$hash\s*=\s*{}/) { 
            splice @outputScript, $i+1, 0, "$hash = {}\n";
        }
    }

    $hashes{$hash} = 1;
}

sub handle_Regex_Grouping_Assignments {
    # handles only very simple groupings
    my $i;
    my $line;
    for ($i = 0; $i < $#outputScript; $i++) {
        $line = $outputScript[$i];
        if ($line =~ /^\s*(\w+)\s*=\s*(\$\d)/) { # for variables
            my $object = $2;
            if ($object =~ /\$\d/) {
                my $var = getPreviousMatch($i);
                if ($var ne "--not_found") {
                    $object = "\\".$object;
                    my $group = $object =~ /(\d)/; 
                    $line =~ s/$object/$var.group($group)/;
                }
            }
        } elsif ($line =~ /^\s*(\w+)\[(\$\w+)\]\s*=\s*(\$\w+)/) { #for hashes and arrays
            my $array = $1;
            my $index = $2;
            my $object = $3;
            
            if ($index =~ /\$\d/ && defined $hashes{$array}) {
                my $var = getPreviousMatch($i);
                if ($var ne "--not_found") {
                    $index = "\\".$index;
                    my ($group) = ($index =~ /(\d)/);
                    $line =~ s/$index/$var.group($group)/;
                }
            } 
            if ($object =~ /\$\d/ && defined $hashes{$array}) {
                my $var = getPreviousMatch($i);
                if ($var ne "--not_found") {
                    $object = "\\".$object; 
                    my ($group) = ($object =~ /(\d)/);
                    $line =~ s/$object/$var.group($group)/;
                }
            }
        }
        $outputScript[$i] = $line;
    }

}

sub getPreviousMatch {
    my ($index) = @_;
    my $var = "--not_found";

    while ($index > $importLine) {
        if ($outputScript[$index] =~ /(\w*)\s*=\s*re.match\(.*?'\(.*?\).*?'.*?\)/) {
            $var = $1;
            last;
        }
        $index--;
    }    
    return $var;
}

# Main code
@scriptToTranslate = <>;
@outputScript = ();
@customFunctions = ();
%hashes = ();

#get import line ready
$importLine = getImportLine();

while (@scriptToTranslate) {
	push @outputScript, translate(0);
}

handle_Regex_Grouping_Assignments();
print @outputScript;

