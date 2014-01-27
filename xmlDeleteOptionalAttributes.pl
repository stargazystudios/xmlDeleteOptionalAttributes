#!/usr/bin/perl -w

#Copyright (c) 2013, Stargazy Studios
#All Rights Reserved

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of Stargazy Studios nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#xmlToHeader searches an input XSD file for ComplexTypes containing optional attributes.
#Any Elements found in the XML document of those types have their optional attributes 
#deleted.

use strict;
use Getopt::Long;
use XML::LibXML;
use File::Basename;
use Data::Dumper;

#TODO Start Here: why is "uid" attribute not being identified and deleted?
										
sub checkTypeAndExpandElement{
	my ($element,$elementPath,$xmlData,$complexTypesHashRef,$elementNamesHashRef) = @_;
	
	if ($element->hasAttribute("type")){
		my $elementType = $element->getAttribute("type");
		
		#if the element's complexType matches a keyword
		if (exists $$complexTypesHashRef{$elementType}){
		
			#check if this element has already been expanded, and if so terminate
			if (exists $$elementNamesHashRef{$elementPath}){
				return;
			}
			
			#otherwise, add the element path to the hash
			else{
				#DEBUG
				#print "Storing $elementPath\n";
				$$elementNamesHashRef{$elementPath} = $elementType;
			}
		}
		
		#process child elements
		foreach my $complexType ($xmlData->findnodes('/xs:schema/xs:complexType[@name="'.$elementType.'"]')){
			foreach my $childElement ($complexType->findnodes("./xs:sequence/xs:element")){
				if ($childElement->hasAttribute("name")){
					my $childElementPath = $elementPath."/".$childElement->getAttribute("name");
					checkTypeAndExpandElement($childElement,$childElementPath,$xmlData,$complexTypesHashRef,$elementNamesHashRef);
				}
			}
		}
	}
}

sub searchElements{
	#Search the passed hash of XSD elements for Complex Type keywords, expanding any that
	#are found to continue the search. As the name of an element can be duplicated within 
	#different types, the hierarchy of the path to the name must be stored along with it.
	#XML element names can not contain spaces, so this character can be used to delineate
	#members of the hierarchy.
	 
	#Loop detection can be made by comparing the hierarchy path element names to the 
	#current one under consideration.
	
	my ($xmlData,$complexTypesHashRef,$elementNamesHashRef) = @_;

	#iterate through all elements
	foreach my $element ($xmlData->findnodes("/xs:schema/xs:element")){
		#check element type against list of Type keywords
		if ($element->hasAttribute("name")){
			#DEBUG
			#print "Processing ".$element->getAttribute("name")."\n";
			checkTypeAndExpandElement($element,"/".$element->getAttribute("name"),$xmlData,$complexTypesHashRef,$elementNamesHashRef);
		}
	}
}
										
my $xmlIn = '';
my $xsdIn = '';
my $outDir = '';

GetOptions(	'xmlIn=s' => \$xmlIn,
			'xsdIn=s' => \$xsdIn,
			'outDir=s' => \$outDir);

#check outDir finishes with a slash if it contains one
if($outDir =~ /^.*[\/].*[^\/]$/){$outDir = "$outDir/";}
else{if($outDir =~ /^.*[\\].*[^\\]$/){$outDir = "$outDir\\";}}

my $parserLibXML = XML::LibXML->new();

#parse xsd schema to find optional attributes, storing hash of ComplexType names, along 
#with an array of optional attribute names.
if(-e $xmlIn && -e $xsdIn){
	my $xmlData = $parserLibXML->parse_file($xsdIn);
	
	if($xmlData){
		my %complexTypes;
		
		#iterate through all complexTypes in the schema
		foreach my $type ($xmlData->findnodes('/xs:schema/xs:complexType')){
			if($type->hasAttribute("name")){
				foreach my $childNode ($type->getChildNodes){
					#find optional attribute nodes
					if($childNode->nodeType eq XML_ATTRIBUTE_NODE){	
						
						my $isRequired = 0;
						if($childNode->hasAttribute("use")){
							if($childNode->getAttribute("use") eq "required"){$isRequired = 1;}
						}
						
						if(!$isRequired){
							if($childNode->hasAttribute("name")){push(@{$complexTypes{$type->getAttribute("name")}},$childNode->getAttribute("name"));}
							else{print STDERR "ERROR: missing \"name\" attribute for XSD attribute node. EXIT\n";}
						}
					}
				}
			}
			else{
				print STDERR "ERROR: missing \"name\" attribute for XSD complexType. EXIT\n";
				exit 1;
			}
		}
		
		#on a second pass, identify which element names are of a ComplexType requiring 
		#attribute deletion
		#-process xs:complexType:
		#-process xs:element:
		my %elementNames;
		my $elementNamesHashRef = \%elementNames;
		
		#recursively search for Elements with keyword types and store hierarchy paths
		searchElements($xmlData,\%complexTypes,$elementNamesHashRef);
		
		#parse xml in file to find Elements, removing any optional attributes
		$xmlData = $parserLibXML->parse_file($xmlIn);
		
		if($xmlData){
			#validate xmlIn with xsdIn
			my $xmlSchema = XML::LibXML::Schema->new('location' => $xsdIn);
			eval {$xmlSchema->validate($xmlData);};
			die $@ if $@;
		
			if($xmlData){						
				foreach my $elementPath (keys %elementNames){
					my $elementType = $elementNames{$elementPath};
					foreach my $attributeName (@{$complexTypes{$elementType}}){
						foreach my $elementInstance ($xmlData->findnodes($elementPath)){
							if($elementInstance->hasAttribute($attributeName)){$elementInstance->removeAttribute($attributeName);}
						}
					}
				}
			}

			#output XMLData to file
			my $outFilePath = '';
			if($outDir){$outFilePath = $outDir.fileparse($xmlIn);}
			else{$outFilePath = $xmlIn;}
			$xmlData->toFile($outFilePath);
		}
		else{
			print STDERR "xmlIn($xmlIn) is not a valid xml file. EXIT\n";
			exit 1;
		}
	}
	else{
		print STDERR "xsdIn($xsdIn) is not a valid xml file. EXIT\n";
		exit 1;
	}
}
else{
	print STDERR "Options --xsdIn --xmlIn are required. EXIT\n";
	exit 1;
}