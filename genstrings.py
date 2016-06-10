#  Created by Johannes Schriewer on 2011-11-30. Modified by Roy Marmelstein 2015-08-05
#  Copyright (c) 2011 planetmutlu.
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  - Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  - Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
#  TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
#  PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
#  OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
#  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
#  PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
#  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
#  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
#  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# This script is heavily copied from: https://github.com/dunkelstern/Cocoa-Localisation-Helper
# Copied from https://github.com/marmelroy/Localize-Swift By QiuYuzhou

import os, re, subprocess
import fnmatch

def fetch_files_recursive(directory, extension):
    matches = []
    for root, dirnames, filenames in os.walk(directory):
      for filename in fnmatch.filter(filenames, '*' + extension):
          matches.append(os.path.join(root, filename))
    return matches


# prepare regexes
localizedStringComment = re.compile('NSLocalizedString\("([^"]*)",\s*"([^"]*)"\s*\)', re.DOTALL)
localizedStringNil = re.compile('NSLocalizedString\("([^"]*)",\s*nil\s*\)', re.DOTALL)
localized = re.compile('Localized\("([^"]*)"[^\n\r]*\)', re.DOTALL)
localizedProperty = re.compile('"([^"]*)".localized', re.DOTALL)# Add By QiuYuzhou
localizedSwift2 = re.compile('"([^"]*)".localized\(\)', re.DOTALL)
localizedSwift2WithFormat = re.compile('"([^"]*)".localizedFormat\([^\n\r]*\)', re.DOTALL)

# get string list
uid = 0
strings = []
for file in fetch_files_recursive('.', '.swift'):
    with open(file, 'r') as f:
        content = f.read()
        for result in localizedStringComment.finditer(content):
            uid += 1
            strings.append((result.group(1), result.group(2), file, uid))
        for result in localizedStringNil.finditer(content):
            uid += 1
            strings.append((result.group(1), '', file, uid))
        for result in localized.finditer(content):
            uid += 1
            strings.append((result.group(1), '', file, uid))
        # Add By QiuYuzhou, Begin
        for result in localizedProperty.finditer(content):
            uid += 1
            strings.append((result.group(1), '', file, uid))
        # Add By QiuYuzhou, End
        for result in localizedSwift2.finditer(content):
            uid += 1
            strings.append((result.group(1), '', file, uid))
        for result in localizedSwift2WithFormat.finditer(content):
            uid += 1
            strings.append((result.group(1), '', file, uid))

# prepare regexes
localizedString = re.compile('"[^=]*=\s*"([^"]*)";')

# Changed By QiuYuzhou, disable for *.xib
# fetch files
#for file in fetch_files_recursive('.', '.xib'):
#    tempFile = file + '.strings'
#    utf8tempFile = file + '.strings.utf8'
#    subprocess.call('ibtool --export-strings-file "' + tempFile + '" "' + file + '" 2>/dev/null', shell=True)
#    subprocess.call('iconv -s -f UTF-16 -t UTF-8 "' + tempFile + '" >"'+utf8tempFile+'" 2>/dev/null', shell=True)
#
#    f = open(utf8tempFile, 'r')
#    for line in f:
#        result = localizedString.match(line)
#        if result:
#            uid += 1
#            strings.append((result.group(1), '', file, uid))
#    f.close()
#
#    os.remove(utf8tempFile)
#    os.remove(tempFile)

# find duplicates
duplicated = []
filestrings = {}
for string1 in strings:
    dupmatch = 0
    for string2 in strings:
        if string1[3] == string2[3]:
            continue
        if string1[0] == string2[0]:
            if string1[2] != string2[2]:
                dupmatch = 1
            break
    if dupmatch == 1:
        dupmatch = 0
        for string2 in duplicated:
            if string1[0] == string2[0]:
                dupmatch = 1
                break
        if dupmatch == 0:
            duplicated.append(string1)
    else:
        dupmatch = 0
        if string1[2] in filestrings:
            for fs in filestrings[string1[2]]:
                if fs[0] == string1[0]:
                    dupmatch = 1
                    break
        else:
            filestrings[string1[2]] = []
        if dupmatch == 0:
            filestrings[string1[2]].append(string1)

print '\n\n\n\n\n'
print '/*\n * SHARED STRINGS\n */\n'

# output filewise
for key in filestrings.keys():
    print '/*\n * ' + key + '\n */\n'

    strings = filestrings[key]
    for string in strings:
        if string[1] == '':
            print '"' + string[0] + '" = "' + string[0] + '";'
            print
        else:
            print '/* ' + string[1] + ' */'
            print '"' + string[0] + '" = "' + string[0] + '";'
            print

# output duplicates
for string in duplicated:
    if string[1] == '':
        print '"' + string[0] + '" = "' + string[0] + '";'
        print
    else:
        print '/* ' + string[1] + ' */'
        print '"' + string[0] + '" = "' + string[0] + '";'
        print