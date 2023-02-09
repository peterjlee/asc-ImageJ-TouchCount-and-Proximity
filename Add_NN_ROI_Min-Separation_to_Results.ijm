/*
	A brute force macro to measure the minimum separation between objects. The minimum spacings are added to the Results table along with the connecting coordinates. The spacing connecting lines can be displayed on the images or animated.
	Distances are measured from object outline to "inline" (perimeter within object).
	Peter J. Lee, Applied Superconductivity Center, NHMFL, Florida State University
	v191210: first working version.
	v191211: Added color choices and prefs saving.
	v191212: Added legend option.
	v191220-v200102: Improved legend.
	v200304 - Added memory flushing component. v200305 added memFlush to restoreExit.
	v200305 Better optimum sampling guess and a few more memory tweaks but there is still a cumulative and persistent memory leak..
	v200722 Added manual macro label and selection of results table using new function.
	v201215 Changed to expandable arrays and fixed unexpected skipping of objects.
	v211022 Updated color choices
	v211108 Updated functions f1: updated functions f2 updated binary check function
	v220705 Reorganized to improve memory use and speed, also allows start at object #>0.  v220706 Also catches up with drawing lines. f1: updated colors and replaced binary[-]Check function with toWhiteBGBinary
	v220708 Now works for color images assuming ROI set has already been created but requires new createROIBinaryImage function. Added more time diagnostics - v220710
	v220720 Adds option to save ROI object numbers for nearest neighbor cluster.
	v220816 If pixel sampling is chosen the adjacent array coordinates will also be sampled.
	v220817 Added dialog option to control re-sampling range and consolidated labeling dialogs. This variant does not use CLIJ. Updated check for plugin function.
	v230105-6 Quick fix for sub-sampling issue on very large images with high object counts (not fully tested).
	v230120 Fixed a typo that crashed macro on 1st memory flush! v230124: Minor syntax optimization.
	v230121-9 Saves last run enabling easier restart. More robust resampling produced much faster analysis without reducing accuracy. Restored ASC default background (white) and foreground (black) throughout for consistency.
	v230130-1: File save check changed from File.exists to File.length>0 as a more reliable indicator of a successful save.
	*/
	macroL = "Add_NN_ROI_Min-Separation_to_Results_v230131.ijm";
	setBatchMode(true);
	requires("1.47r"); /* not sure of the actual latest working version but 1.45 definitely doesn't work */
	saveSettings(); /* To restore settings at the end */
	prefsNameKey = "asc.NN.ROI.sep.Prefs.";
	/* set the following standard ASC foreground and background colors for consistency */
	run("Colors...", "foreground=black background=white selection=yellow");
	prevRunImage = verifiedGetSet("get",prefsNameKey+"LastRunImage",false,"");
	/* (setOrGet,key,altPath) setOrGet should be "set" or "get", key is the full prefs key (the key should end in "Image", "Results", or "ROIs") */
	prevRunROI = verifiedGetSet("get",prefsNameKey+"LastRunROIs",false,"");
	prevRunResults = verifiedGetSet("get",prefsNameKey+"LastRunResults",false,"");
	prefsDelimiter = "|";
	plusminus = fromCharCode(0x00B1);
	leq = fromCharCode(0x2264);
	dateCode = getDateCode();
	setOption("ExpandableArrays", true); /* In ImageJ 1.53g and later, arrays automatically expand in size as needed */
	/*	The above should be the defaults but this makes sure (black particles on a white background) https://imagej.net/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	imageN = nImages;
	nROIs = roiManager("count");
	nRes = nResults;
	if (imageN==0 || nROIs==0 || nRes==0){
		if(prevRunImage!="" && prevRunROI!="" && prevRunResults!=""){ /* Looks for a previous run to restore */
			Dialog.create(macroL + ": Continuation options");
			preOptions = newArray("Just exit the macro","Use files selected below","Skip reloading files and continue with macro to generate new ROIs and Results");
			Dialog.addRadioButtonGroup(imageN + "images, " + nROIs + " ROIs, and " + nRes + " results are open but there is a previous run that can be restored:",preOptions,3,1,preOptions[1]);
			Dialog.addCheckbox("Open image file below",1-minOf(imageN,1));
			Dialog.addFile("Restore previous run image:",prevRunImage);
			Dialog.addCheckbox("Open ROI set below",1-minOf(nROIs,1));
			Dialog.addFile("Previous run ROI set:",prevRunROI);
			Dialog.addCheckbox("Open Results below",1-minOf(nRes,1));
			Dialog.addFile("Previous run Results table:",prevRunResults);
			Dialog.show();
			preOption = Dialog.getRadioButton();
			if (startsWith(preOption,"Just")) restoreExit("Goodbye, see you again soon");
			else if(startsWith(preOption,"Use")){
				restoreImage = Dialog.getCheckbox();
				restoreImagePath = Dialog.getString();
				restoreROIs = Dialog.getCheckbox();
				restoreROIPath = Dialog.getString();
				restoreResults = Dialog.getCheckbox();
				restoreResultsPath = Dialog.getString();
				if (File.exists(restoreImagePath)){
					if (File.length(restoreImagePath)>0 && restoreImage){
						IJ.log("Image restored from: " + restoreImagePath);
						open(restoreImagePath);
					}
				}
				if (File.exists(restoreROIPath)){
					if (File.length(restoreROIPath)>0 && restoreROIs){
						if (nROIs>0){
							roiManager("reset");
							IJ.log("Previous " + nROIs + " ROIs replaced from: " + restoreROIPath);
						}
						else IJ.log("ROIs restored from:\n" + restoreROIPath);
						roiManager("open", restoreROIPath);
					}
				}
				if (File.exists(restoreResultsPath)){
					if (File.length(restoreResultsPath)>0 && restoreResults){
						IJ.log("Results table restored from:\n" + restoreResultsPath);
						File.open(restoreResultsPath);
					} 
				}
			}
		}
		if (nImages==0) File.openDialog("At least one open image is required, please select one");
		imageN = nImages;
		nROIs = roiManager("count");
		nRes = nResults;
	}
	if (imageN==0) restoreExit("Sorry, failure to find or restore previous images");
	else{
		t = getTitle();
		fileNameNE = File.getNameWithoutExtension(t);
		defImagePath = getDir("image");
		null = verifiedGetSet("set",prefsNameKey+"LastRunImage",false,"");
	} 
	if (checkForEdgeObjects() && roiManager("count")!=0){
		if (getBoolean("There are edge objects AND ROIs; Do you want to remove the edge objects and reset the ROIs?")) {
			roiManager("reset");
			removeBlackEdgeObjects;
		}
	}  /* macro does not make much sense if there are edge objects but perhaps they are not included in ROI list (you can cancel out of this). if the object removal routine is run it will also reset the ROI Manager list if it already contains entries */
	nROIs = checkForRoiManager();
	overlayN = Overlay.size;
	fCycles = floor(nROIs/10); /* How frequently to check memory usage */
	run("Options...", "count=1 do=Nothing"); /* The binary count setting is set to "1" for consistent outlines */
	imageWidth = getWidth();
	imageHeight = getHeight();
	dimProd = imageWidth*imageHeight;
	dimSum = imageWidth+imageHeight;
	checkForUnits();
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf = (pixelWidth+pixelHeight)/2; /* ---> add here the side size of 1 pixel in the new calibrated units (e.g. lcf=5, if 1 pixels is 5mm) <--- */
	lcfSq = pow(lcf,2);
	/* create the dialog prompt */
	selectResultsWindow(); /* allows you to choose from multiple windows */
	if(!isNaN(Table.get("Perim.",0))) Array.getStatistics(Table.getColumn("Perim."), minPerim, maxPerim, meanPerim, null) ;
	else exit("Sorry, Perim values in table are needed for this macro");
	reRun = false;
	if(!isNaN(Table.get("MinSepROI1",0))){
		MinSepROI1s = Table.getColumn("MinSepROI1");
		showStatus("Finding last measured object");
		for (i=0,foundNaN=false;i<nROIs && !foundNaN;i++){
			showProgress(i,nROIs);
			if (isNaN(MinSepROI1s[i])){
				foundNaN=true;
				reRun = true;
				lastMinSepROI = i-1;
			}
		}
	}
	/* Create a new image for just the ROIs allowing you to color an original color image or one with other perhaps a scale bar that interferes with the bounding box */
	createROIImage(t+"_ROIBinary",imageWidth,imageHeight,false,false,0,false);
	/* options: newTitle,imageWidth,imageHeight,blackBackground,labelObjects,expandN,hollow;  blackBackground and labelObjects options are true-false */
	selectWindow(t+"_ROIBinary");
	run("Select Bounding Box");
	getSelectionBounds(minBX, minBY, widthB, heightB);
	maxBX = minBX + widthB;
	maxBY = minBY + heightB;
	run("Select None");
	totalPL = nROIs * meanPerim;
	totalPPx = round(totalPL/lcf);
	maxPerimPx = maxPerim/lcf;
	minPerimPx = minPerim/lcf;
	orPixSkip = round(minPerimPx/12);
	destPixSkip = round(minPerimPx/12);
	resamplePx = round(maxPerimPx/6);
	dLW = maxOf(1,round(imageWidth/1024)); /* default line width */
	nResamplingSuccess = 0;
	totalMinDistPx = 0;
	memFlush(200); /* This macro needs all the help it can get */
	run("Appearance...", " "); if(is("Inverting LUT")) run("Invert LUT"); /* For consistency this macro does not use Inverting LUTs */
	Dialog.create("Options for: " + macroL);
		Dialog.addMessage("Bounding box for all objects: x = " + minBX + "-" + maxBX + ", y = "  + minBY + "-" + maxBY);
		if(reRun){
			if(lastMinSepROI<nROIs-1) Dialog.addNumber("This macro was previously run to object " + lastMinSepROI + ", run from the next object?",lastMinSepROI+1,0,5,"");
			else Dialog.addNumber("This macro was previously run to completion, from which object to you want to rerun?",0,0,5,"");
		}
		else Dialog.addNumber("Run from object ",0,0,5,"");
		Dialog.addNumber("No. of object distance sets \("+leq+"6\) to be added to Results Table:", 1, 0, 6,"of " + nROIs + " ROIs");
		Dialog.addNumber("No. of adjacent ROIs \(by centroid\) to included in search:", minOf(6,nROIs-1), 0, 6,"adjacent ROIs");
		Dialog.addCheckbox("Add column listing adjacent ROIs selected above",true); /* Could be used for cluster analysis */
		Dialog.addCheckbox("Add \(WIDE!\) column listing adjacent center-center distances for adjacent ROIs",false); /* Could be used for cluster analysis */
		Dialog.addMessage("This brute force approach is a little slow but it can be sped up by x3 \nby sub-sampling the perimeter points based in the minimum perimeter/12:");
		Dialog.addNumber("Random sampling of origin outline pixels in initial search:", orPixSkip, 0, 3,"pixels skipped");
		Dialog.addNumber("Random sampling of nearest neighbor ROI perimeter pixels in initial search:", destPixSkip, 0, 3,"pixels skipped");
		Dialog.addMessage("Default resampling below using the default maximum perimeter/6 and the \ndefault values typically restores full accuracy");
		Dialog.addNumber("Full random re-sampling of adjacent array indices after sub-sampling above:",resamplePx, 0, 3,plusminus+"pixels");
		Dialog.addCheckbox("Draw connectors showing shortest distance \(no significant impact on time\)",false);
		Dialog.addMessage("Because the coordinates are shuffled each run, different connections may be\ndrawn each run if there is more than one closest location pair");
		if(overlayN>0) Dialog.addCheckbox("Remove previous " + overlayN + " overlays?",true);
		Dialog.addMessage("This macro can use a lot of memory, the current memory usage is " + IJ.freeMemory());
		Dialog.addCheckbox("Run with memory and additional time reporting \(no significant time increase\)",false);
		Dialog.addCheckbox("Run in debug mode \(very slow\)",false);
	Dialog.show;
		startObject = minOf(nROIs-1,Dialog.getNumber());
		maxTableObjects = minOf(nROIs-1,Dialog.getNumber); /* put a limit of how many adjacent filaments to report */
		maxNNROIs = minOf(nROIs-1,Dialog.getNumber);
		nnROIL = Dialog.getCheckbox();
		nnROIDL = Dialog.getCheckbox();
		outlinePixSkip = Dialog.getNumber();
		destPixSkip = Dialog.getNumber();
		resamplePx =  Dialog.getNumber();
		drawConnector = Dialog.getCheckbox();
		if(overlayN>0) removePreviousOverlays = Dialog.getCheckbox();
		else removePreviousOverlays = false;
		mDiagnostics = Dialog.getCheckbox();
		debugMode = Dialog.getCheckbox();
	if(debugMode) setBatchMode("exit & display"); /* exit batch mode */
	if (removePreviousOverlays){
		selectWindow(t);
		while(Overlay.size>0) Overlay.remove;
		selectWindow(t+"_ROIBinary");
	} 
	if (drawConnector){
		colorChoicesMono = newArray("white", "black", "off-white", "off-black", "light_gray", "gray", "dark_gray");
		colorChoicesStd = newArray("red", "green", "blue", "cyan", "magenta", "yellow", "pink", "orange", "violet");
		colorChoicesMod = newArray("garnet", "gold", "aqua_modern", "blue_accent_modern", "blue_dark_modern", "blue_modern", "blue_honolulu", "gray_modern", "green_dark_modern", "green_modern", "green_modern_accent", "green_spring_accent", "orange_modern", "pink_modern", "purple_modern", "red_n_modern", "red_modern", "tan_modern", "violet_modern", "yellow_modern");
		colorChoicesNeon = newArray("jazzberry_jam", "radical_red", "wild_watermelon", "outrageous_orange", "supernova_orange", "atomic_tangerine", "neon_carrot", "sunglow", "laser_lemon", "electric_lime", "screamin'_green", "magic_mint", "blizzard_blue", "dodger_blue", "shocking_pink", "razzle_dazzle_rose", "hot_magenta");
		colorChoices = Array.concat(colorChoicesMono,colorChoicesStd,colorChoicesMod,colorChoicesNeon);
		defaultColorOrder = Array.trim(colorChoicesStd,6);
		colorString = call("ij.Prefs.get", prefsNameKey+"LineColors","red|cyan|pink|green|blue|yellow");
		colorPrefs = split(colorString, prefsDelimiter);
		colorPrefs = Array.concat(colorPrefs,defaultColorOrder);
		maxLines = minOf(maxTableObjects,6);
		defThickns = newArray(maxLines);
		Array.fill(defThickns, parseInt(dLW));
		defThicknString = arrayToString(defThickns,prefsDelimiter);
		thicknString = call("ij.Prefs.get", prefsNameKey+"LineThickness",defThicknString);
		thicknPrefs = split(thicknString, prefsDelimiter);
		thicknPrefs = Array.concat(thicknPrefs,defThickns);
		liveDraw = false;
		fontSize = maxOf(14,round(dimSum/60));
		fontNameChoice = getFontChoiceList();
		iFN = indexOfArray(fontNameChoice, call("ij.Prefs.get", "asc.legend.font.name",fontNameChoice[0]),0);
		fontStyleChoice = newArray("bold", "italic", "bold italic", "unstyled");
		iFS = indexOfArray(fontStyleChoice, call("ij.Prefs.get", "asc.legend.font.style",fontStyleChoice[0]),0);
		Dialog.create("Connector Overlay Line Drawing and Legend Options");
			for(lineP=0;lineP<maxLines; lineP++){
				lW = parseInt(thicknPrefs[lineP]);
				if (isNaN(lW)) lW = 1;
				Dialog.addChoice("Line color for distance " + lineP+1, colorChoices, colorPrefs[lineP]);
				Dialog.addNumber("Line width for distance " + lineP+1, lW, 0, 3,"pixels");
			}
			Dialog.addCheckbox("Create Animation Line Stack?",false);
			Dialog.addCheckbox("Create Legend?",false);
			Dialog.addNumber("Font Size", fontSize, 0,3,"pixels");
			Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[iFN]);
			Dialog.addChoice("Font style*:", fontStyleChoice, fontStyleChoice[iFS]);
			Dialog.addRadioButtonGroup("Legend Size: Fits Image", newArray("Height", "Width"),1,2,"Width");
			Dialog.addRadioButtonGroup("Add to image:", newArray("No", "Right/Top", "Left/Bottom"),1,3,"Left/Bottom");
			Dialog.addMessage("Combining the legend with the image creates a new\nflat combination image and closes the legend window.");
		Dialog.show;
			lineColors = newArray(maxLines);
			lineThickness = newArray(maxLines);
			for(lineN=0; lineN<maxLines; lineN++){
				lineColors[lineN] = Dialog.getChoice;
				lineThickness[lineN] = Dialog.getNumber;
			}
			animStack = Dialog.getCheckbox;
			createLegend = Dialog.getCheckbox;
			fontSize = Dialog.getNumber;
			fontName = Dialog.getChoice;
			fontStyle = Dialog.getChoice;
			legendFit = Dialog.getRadioButton;
			legendLoc = Dialog.getRadioButton;
		maxLines = minOf(maxTableObjects,6);
		colorsString = arrayToString(lineColors,prefsDelimiter);
		thicknessString = arrayToString(lineThickness,prefsDelimiter);
		call("ij.Prefs.set", prefsNameKey+"LineColors", colorsString);
		call("ij.Prefs.set", prefsNameKey+"LineThickness", thicknessString);
	}
	else {
		createLegend = false;
		animStack = false;
	}
	if (createLegend)	closeImageByTitle("Legend"); /* Close previous legend */
	startTime = getTime();
	IJ.log("-----\n\nMacro: " + macroL + "\n_____________\nImage used for count: " + t);
	IJ.log("Original magnification scale factor used = " + lcf + " with units: " + unit);
	IJ.log("Maximum object separations to be added to table = " + maxTableObjects);
	if (outlinePixSkip>0) IJ.log(outlinePixSkip + " outline pixels skipped in initial search");
	if (destPixSkip>0) IJ.log(destPixSkip + " destination pixels skipped in initial search");
	if(mDiagnostics) IJ.log("Starting memory: " + IJ.freeMemory);
	if (animStack){
		tA = "Separation Line Animation Stack";
		selectWindow(t);
		run("Duplicate...", "title=[Separation Line Animation Stack]");
		run("RGB Color");
	}
	selectWindow(t+"_ROIBinary");
	run("Select None");
	/* Generate outline pixel coordinate arrays and matching object labels */
	/* 			Part 1: Create Inline (perimeter pixels within object) of Perimeter image for all objects */
	run("Duplicate...", "title=binaryInline");
	if(!is("binary")){
		run("Convert to Mask");
		if (is("Inverting LUT")) run("Invert LUT");
		if(getPixel(0,0)==0) run("Invert");
	}
	/* Created binaryInline is black image with a white interior border around each of the ROIs */
	createROIImage("labeledInline",imageWidth,imageHeight,true,true,-1,true);
	/* function options: newTitle,imageWidth,imageHeight,blackBackground,labelObjects,expandN,hollow;  blackBackground and labelObjects options are true-false */
	/* Arrays containing all inLine pixel coordinates and ROI-mapped intensities - with optional sub-sampling */
	allInlinePxXs = newArray(); /* All inline pixels: x coordinates */
	allInlinePxYs = newArray(); /* All inline pixels: y coordinates */
	allInlinePxROIs = newArray(); /* All inline pixels: ROI labels */
	/* Get all perimeter coordinates */
	showStatus("Acquiring all perimeter coordinates and ROI-ID-labels");
	for (x=minBX,oPxls=0; x<maxBX; x++){  /* oPxls is Counter for outline/inline pixels */
		showProgress(x, maxBX);
		showStatus("Acquiring all perimeter coordinates and ROI-ID-labels");
		for (y=minBY; y<maxBY; y++){
			pixelIntInline = getPixel(x, y);
			if(pixelIntInline!=0) { /* The ROI labeled image should be black with each ROI adding 1 intensity value so ROI[0] should have an intensity of 1 */
				allInlinePxXs[oPxls] = x;
				allInlinePxYs[oPxls] = y;
				allInlinePxROIs[oPxls] = pixelIntInline - 1; /* Each intensity value is the ROI# starting at 1 but ROI selection i number starts at zero */ 
				oPxls++;
			}
		}
	}
	IJ.log("Total perimeter pixels = " + totalPPx + " \(original perimeter: " + totalPL + " " + unit + "\)");
	IJ.log("Total perimeter coordinate sets = " + oPxls);
	if(!debugMode){
		closeImageByTitle("binaryInline");
		closeImageByTitle("labeledInline");
		closeImageByTitle(t+"_ROIBinary");
	}
	if (destPixSkip>0){
		/* randomize coordinates for better subsampling later */
		showStatus("Shuffling all destination coordinates");
		randomIndexArray = createRandomIndexArray(oPxls);
		Array.sort(randomIndexArray, allInlinePxXs, allInlinePxYs,allInlinePxROIs);
		showStatus("Finished shuffling all destination coordinates");
	}
	selectWindow(t);
	run("Select None");
	/* Catch up on drawing lines from previous start */
	if (startObject>0 && drawConnector){
		showStatus("Redrawing previously determined lines");
		for (i=0; i<startObject; i++){
		showProgress(i,startObject);
		for (n=0; n<maxTableObjects; n++){
				minXOL = getResult("MinSepThisROIx"+(n+1), i);
				minYOL = getResult("MinSepThisROIy"+(n+1), i);
				minXL = getResult("MinSepNNROIx"+(n+1), i);
				minYL = getResult("MinSepNNROIy"+(n+1), i);
				if(n<maxLines){
					setLineWidth(lineThickness[n]);
					setColorFromColorName(lineColors[n]);
					Overlay.drawLine(minXOL, minYOL, minXL, minYL);
					Overlay.show;
				}
			}
		}
	}
	tempROIpath = defImagePath + "_tempROIs_" + dateCode + ".zip";
	/* the ROI manager randomly clears so this is part of a workaround for that */
	tempROIpath = verifiedGetSet("set",prefsNameKey+"tempROIs",true,tempROIpath);
	if (tempROIpath=="") IJ.log("Warning: ROI manager has been cleared");
	oCXs = Table.getColumn("X");
	oCYs = Table.getColumn("Y");
	if(nnROIL) nnROIsList = newArray();
	if(nnROIDL) nnROIDsList = newArray();
	startSearch = getTime();
	for (oROI=startObject,flushCount=0; oROI<nROIs; oROI++){
		showProgress(oROI, nROIs);
		timeLeft = getTimeLeftTxt(startSearch,startObject,oROI,nROIs);
		if (oROI==startObject) statusMessageNNSearch = "Analyzing object "+ oROI + " out of " + nROIs;
		else statusMessageNNSearch = "Analyzing object "+ oROI + " out of " + nROIs + ", time left: " + timeLeft;
		showStatus(statusMessageNNSearch);
		/* Create set of true ROI outline (line external to object) coordinates - distances are measure inline-to-outline
		They are created here for each individual ROI because outlines of adjacent ROIs may overlap.
		*/
		newImage("ROIOutline", "8-bit white", imageWidth, imageHeight, 1);
		run("Select None");
		roiManager("Select", oROI);
		run("Enlarge...", "enlarge=1 pixel");
		getSelectionBounds(xMin, yMin, outWidth, outHeight);
		run("Set...", "value=0");
		roiManager("Select", oROI);
		run("Set...", "value=255");
		run("Select None");
		outlinePxXs = newArray();
		outlinePxYs = newArray();
		xMin -= 1;	yMin -= 1; /* Adjust bounds for Outline */
		xMax = xMin + outWidth + 2;
		yMax = yMin + outHeight + 2;
		for (iM=xMin,rPxls=0; iM<xMax; iM++){
			for (jM=yMin; jM<=yMax; jM++){
				pixelIntROIOut = getPixel(iM, jM);
				if(pixelIntROIOut==0) {  /* Only the "outline" should be black */
					outlinePxXs[rPxls] = iM;
					outlinePxYs[rPxls] = jM;
					rPxls++;
				}
			}
		}
		if (outlinePixSkip>0){
			/* randomize coordinates for better sub-sampling later */
			randomIndexArray = createRandomIndexArray(rPxls);
			Array.sort(randomIndexArray, outlinePxXs, outlinePxYs);
		}
		if(!debugMode) closeImageByTitle("ROIOutline");
		/* End of Outline coordinate set creation */
		selectWindow(t);
		/* Filter inline destination coordinate set so that it only includes adjacent ROIs */
			/* First create a list of the distances to all the other ROI centers */
		oCDSqs = newArray();
		// iL=0; //?
		nnROIs = newArray();
		for(iO=0,c=0;iO<nROIs; iO++){
			if (iO!=oROI){	
				oCDSqs[c] = pow(oCXs[oROI]-oCXs[iO],2) + pow(oCYs[oROI]-oCYs[iO],2);
				nnROIs[c] = iO;
				c++;
			}
		}
		Array.sort(oCDSqs,nnROIs);
		oCDSqs = Array.trim(oCDSqs,maxNNROIs);
		nnROIs = Array.trim(nnROIs,maxNNROIs);
		if (debugMode){
			Array.print(nnROIs);
			Array.print(oCDSqs);
		}
		/* Filter coordinate arrays so they only include nearest ROIs limited by dialog option creating new filter arrays */
		allInlinePxROIsF = newArray(); /* NN ROIs only */
		allInlinePxXsF = newArray(); /* NN x Coords only */
		allInlinePxYsF = newArray(); /* NN y Coords only */
		oPxlsF = 0;
		nnROILString="";
		nnROIDLString="";
		for (n=0; n<maxNNROIs; n++){
			if (nnROIL) nnROILString += "" + nnROIs[n] + "|";
			if (nnROIDL) nnROIDLString += "" + d2s(sqrt(oCDSqs[n]),1) + "|";
			for (f=0; f<oPxls; f++){
				if (allInlinePxROIs[f]==nnROIs[n]) {
					allInlinePxXsF[oPxlsF] = allInlinePxXs[f];
					allInlinePxYsF[oPxlsF] = allInlinePxYs[f];
					allInlinePxROIsF[oPxlsF] = nnROIs[n];
					oPxlsF++;
				}
			}
		}
		if (nnROIL){
			while(endsWith(nnROILString,"|")) nnROILString = substring(nnROILString,0,lastIndexOf(nnROILString,"|"));
			setResult("NN_ROIs\(by_centroid\)",oROI,nnROILString);
			nnROIsList[oROI] = nnROILString;
		}
		if (nnROIDL){
			while(endsWith(nnROIDLString,"|")) nnROIDLString = substring(nnROIDLString,0,lastIndexOf(nnROIDLString,"|"));
			setResult("NN_ROI Dist\(by_centroid\)",oROI,nnROIDLString);
			nnROIDsList[oROI] = nnROIDLString;
		} 
		/* Create or reset distance arrays for other objects */
		minDSqs = newArray();
		minDROI = newArray();
		minXs = newArray();
		minYs = newArray();
		minXOs = newArray();
		minYOs = newArray();
		/* For each ROI outline point find the min dist etc. to every inLine coordinate of the other ROIs */
		for (dROI=0; dROI<maxNNROIs; dROI++){
			cCDSq = oCDSqs[dROI]/lcfSq;
			/* Find nearest in-line coordinates for every destination ROI */
			minDSq = cCDSq; /* this should be greater than the ctr-ctr distance squared  - oCDSqs are scaled units */
			minSearchIncomplete = true;
			nnDROI = nnROIs[dROI];
			dROIbkp = dROI;
			coordN = 0;
			minX = dimSum;
			minY = dimSum;
			minXO = dimSum;
			minYO = dimSum;
			while(minX>=dimSum-1){
				for (rPx=0; rPx<rPxls; rPx++){ /* for all originating ROI outline pix */
					x1 = outlinePxXs[rPx];
					y1 = outlinePxYs[rPx];
					for (dROIpx=0; dROIpx<allInlinePxROIsF.length; dROIpx++){  /* for all inLine perimeter pixels */
						if(allInlinePxROIsF[dROIpx]==nnDROI) { /* skip all except destination ROI */
							coordN++;
							x2 = allInlinePxXsF[dROIpx];
							y2 = allInlinePxYsF[dROIpx];
							distSq = pow(x1-x2,2) + pow(y1-y2,2); /* note this this the sqrt is not applied until the result is determined for the table */
							if (distSq < minDSq){
								minDSq = distSq;
								minX = x2;
								minY = y2;
								minXO = x1;
								minYO = y1;
							}
						}
						if(minDSq!=cCDSq && minX<dimSum) dROIpx += destPixSkip;
					}
					if(minDSq!=cCDSq && minX<dimSum) rPx += outlinePixSkip;
				}
				dimSum++;
			}
			if(minX==dimSum) IJ.log("Failure to find an adjacent ROI separation for oROI " + oROI + ", dROI " + dROI + ",\nprobably an image thresholding or ROI mismatch issue");
			if (outlinePixSkip>0 || destPixSkip>0){
				dMinXMin = maxOf(0,minX-resamplePx);
				dMinXMax = minOf(dROIpx,minX+resamplePx);
				dMinYMin = maxOf(0,minY-resamplePx);
				dMinYMax = minOf(dROIpx,minY+resamplePx);
				oMinXMin = maxOf(xMin,minXO-resamplePx);
				oMinXMax = minOf(xMax,minXO+resamplePx);
				oMinYMin = maxOf(yMin,minYO-resamplePx);
				oMinYMax = minOf(yMax,minYO+resamplePx);
				for (rPx=0; rPx<rPxls; rPx++){ /* for all originating ROI outline pix */
					x1 = outlinePxXs[rPx];
					y1 = outlinePxYs[rPx];
					if (x1>=oMinXMin && x1<=oMinXMax && y1>=oMinYMin && y1<=oMinYMax){
						for (dROIpx=0; dROIpx<oPxlsF; dROIpx++){  /* for all inLine perimeter pixels */
							if(allInlinePxROIsF[dROIpx]==nnROIs[dROI]) { /* skip all except destination ROI */
								x2 = allInlinePxXsF[dROIpx];
								y2 = allInlinePxYsF[dROIpx];
								if (x2>=dMinXMin && x2<=dMinXMax && y2>=dMinYMin && y2<=dMinYMax){
									distSq = pow(x1-x2,2) + pow(y1-y2,2); /* note this this the sqrt is not applied until the result is determined for the table */
									if (distSq < minDSq){
										minDSq = distSq;
										minX = x2;
										minY = y2;
										minXO = x1;
										minYO = y1;
										nResamplingSuccess++;
									}
								}
							}
						}
					}
				}
			}
			minDSqs[dROI] = minDSq;
			minDROI[dROI] = nnROIs[dROI];
			minXs[dROI] = minX;
			minYs[dROI] = minY;
			minXOs[dROI] = minXO;
			minYOs[dROI] = minYO;
		}
		Array.sort(minDSqs,minDROI,minXs,minYs,minXOs,minYOs);
		selectWindow(t);
		for (n=0; n<maxTableObjects; n++){
			setResult("MinSepROI"+(n+1), oROI, minDROI[n]);
			minSepPx = sqrt(minDSqs[n]);
			setResult("MinSepROI"+(n+1)+"\(px\)", oROI, minSepPx);
			totalMinDistPx += minSepPx;
			if (lcf!=1) setResult("MinSepROI"+(n+1)+"\("+unit+"\)", oROI, lcf*minSepPx);
			setResult("MinSepThisROIx"+(n+1), oROI, minXOs[n]);
			setResult("MinSepThisROIy"+(n+1), oROI, minYOs[n]);
			setResult("MinSepNNROIx"+(n+1), oROI, minXs[n]);
			setResult("MinSepNNROIy"+(n+1), oROI, minYs[n]);
			if (drawConnector){
				if(n<maxLines){
					setLineWidth(lineThickness[n]);
					setColorFromColorName(lineColors[n]);
					Overlay.drawLine(minXOs[n], minYOs[n], minXs[n], minYs[n]);
					Overlay.show;
				}
			}
		}
		flushCount++;
		if (flushCount==fCycles) {
			updateResults();
			mC = parseInt(IJ.currentMemory());
			mX = parseInt(IJ.maxMemory());
			mCP = mC*(100/mX);
			if(mDiagnostics && mCP>50) IJ.log("Memory before flush: " + IJ.freeMemory);
			if (mCP>90) {
				Dialog.create(mCP + "% of IJ memory has been used, analyzing object " + oROI + " out of " + nROIs);
				highMemOptions = newArray("Keep going until the script inevitably crashes?","Exit but save current Results and ROI list for restart","Just exit macro");
				Dialog.addRadioButtonGroup("What would you like to do now?",highMemOptions,3,1,highMemOptions[1]);
				Dialog.addDirectory("Folder for saving work in progress:",defImagePath);
				Dialog.addFile("Results filename:",fileNameNE+"_Results_" + dateCode + ".csv");
				Dialog.addFile("ROI filename:",fileNameNE+"_ROIs_" + dateCode + ".zip");
				Dialog.show;
				leaveChoice = Dialog.getRadioButton();
				if (!startsWith(leaveChoice,"Keep")){
					if (startsWith(leaveChoice,"Exit but")){
						saveDir = Dialog.getString();
						resultsPath = saveDir + Dialog.getString();
						roiPath = saveDir + Dialog.getString();
						if (verifiedGetSet("set",prefsNameKey+"LastRunResults",true,resultsPath)=="") IJ.log("Failed to save\n" + resultsPath);
						if (verifiedGetSet("set",prefsNameKey+"LastRunROIs",true,roiPath)=="") IJ.log("Failed to save\n" + roiPath);
					}
					restoreExit("Goodbye, to free up memory you will need to close ImageJ/Fiji and restart");
				}
			}
			else if (mCP>50){
				if(mDiagnostics) IJ.log("mC = " + mC + ", mX = " + mX + ", mCP = " + mCP);
				memFlush(200); /* Applies 3 memory clearing commands from a function with "fWait"" wait times */
				if(mDiagnostics){
					IJ.log("Memory after flush: " + IJ.freeMemory);
					memFlushRecovered = mC - parseInt(IJ.currentMemory());
					IJ.log("Memory recovered by memory flush \(MB\): " + memFlushRecovered);
				}
			}
			flushCount = 0;
		}
	}
	if (outlinePixSkip>0 || destPixSkip>0) IJ.log("Resampling of " + plusminus+resamplePx + " pixels: " +nResamplingSuccess+ " closer distances");
	updateResults();
	if (animStack){
		if(mDiagnostics) {
			preAnimSecs = (getTime()-startTime)/1000;
			preAnimMins = floor(preAnimSecs/60);
			IJ.log("Run time = " + preAnimMins + " mins " + preAnimSecs-60*preAnimMins + " s");
		}
		selectWindow(tA);
		for (i=0; i<nROIs; i++){
			for (n=0; n<maxTableObjects; n++){
				minXOL = getResult("MinSepThisROIx"+(n+1), i);
				minYOL = getResult("MinSepThisROIy"+(n+1), i);
				minXL = getResult("MinSepNNROIx"+(n+1), i);
				minYL = getResult("MinSepNNROIy"+(n+1), i);
				if(n<maxLines){
					if (animStack) newImage("Animation Frame", "8-bit white", imageWidth, imageHeight, 1);
					setLineWidth(lineThickness[n]);
					setColorFromColorName(lineColors[n]);
					Overlay.drawLine(minXOL, minYOL, minXL, minYL);
					Overlay.show;
					if (animStack){
						run("Flatten");
						rename("tempFrame");
						addImageToStack(tA,t);
						closeImageByTitle("tempFrame");
						closeImageByTitle("Animation Frame");
					}
				}
			}
		}
	}
	if(mDiagnostics && animStack) {
		animSecs = (getTime()-preAnimSecs)/1000;
		animMins = floor(animSecs/60);
		IJ.log("Animation took  = " + animMins + " mins " + animSecs-60*animMins + " s");
	}
	selectWindow(t);
	if (createLegend){
		setFont(fontName,fontSize, fontStyle);
		xStart = fontSize/2;
		yStart = 1.5*fontSize;
		lineHeight = 1.5*fontSize;
		if (legendFit == "Height"){
			legendHeight = imageHeight;
			legendWidth = fontSize * 3.5;
			extraLegendLines = floor(maxLines*1.5*fontSize/imageHeight);
			legendWidth += extraLegendLines*fontSize*4.5;
		}else {
			legendHeight = fontSize * 2;
			legendWidth = imageWidth;
			extraLegendLines = floor((xStart + maxLines*5*fontSize)/imageWidth);
			legendHeight += extraLegendLines*fontSize*1.5;
		}
		if (legendLoc=="No") newImage("Legend", "RGB", legendWidth, legendHeight,1);
		else {
			if(animStack){
				selectWindow(tA);
				Stack.setSlice(0);
			}
			else {
				run("Flatten");
				rename(File.nameWithoutExtension + "&Legend");
			}
			if (legendLoc == "Right/Top"){
				if (legendFit == "width"){ /* Legend-Top */
					newImageHeight = imageHeight + legendHeight;
					run("Canvas Size...", "width=&imageWidth height=&newImageHeight position=Bottom-Left");
				}
				else if (legendFit == "height"){ /* Legend-Right */
					newImageWidth = imageWidth + legendWidth;
					run("Canvas Size...", "width=&newImageWidth height=&imageHeight position=Bottom-Left");
					xStart += imageWidth;
				}
			}
			else if (legendLoc == "Left/Bottom"){
				if (legendFit == "width"){ /* Legend-Bottom */
					newImageHeight = imageHeight + legendHeight;
					run("Canvas Size...", "width=&imageWidth height=&newImageHeight position=Top-Left");
					yStart += imageHeight;
				}
				else if (legendFit == "height"){ /* Legend-Left */
					newImageWidth = imageWidth + legendWidth;
					run("Canvas Size...", "width=&newImageWidth height=&imageHeight position=Top-Right");
				}
			}
			legendWidth = getWidth;
			legendHeight = getHeight;
		}
		if (legendFit == "Height"){
			for(lineP=0;lineP<maxLines; lineP++){
				setLineWidth(lineThickness[lineP]);
				setColorFromColorName(lineColors[lineP]);
				drawLine(xStart,yStart,xStart + 1.5*fontSize,yStart);
				drawString(lineP+1,xStart + 2*fontSize,yStart + 0.75*fontSize);
				yStart += 1.5*fontSize;
				if(yStart+1.5*fontSize>=imageHeight){
					xStart = 0.5*fontSize;
					yStart += 1.5*fontSize;
				}
			}
		}
		if (legendFit == "Width"){
			for(lineP=0;lineP<maxLines; lineP++){
				setLineWidth(lineThickness[lineP]);
				setColorFromColorName(lineColors[lineP]);
				drawLine(xStart,yStart-0.75*fontSize,xStart+1.5*fontSize,yStart-0.75*fontSize);
				drawString(lineP+1,xStart + 2*fontSize,yStart);
				xStart += 4.5*fontSize;
				if(xStart + 4.5*fontSize>=imageWidth){
					xStart = 0.5*fontSize;
					yStart += 1.5*fontSize;
				}
			}
		}
	}
	Overlay.show;
	setBatchMode("exit & display"); /* exit batch mode */
	run("Select None");
	fullSecs = (getTime()-startTime)/1000;
	fullMins = floor(fullSecs/60);
	summaryTxt = "Separation Macro Finished: " + nROIs + " objects analyzed in " + (getTime()-startTime)/1000 + "s.";
	showStatus(summaryTxt);
	summaryTxt += "\nRun time = " + fullMins + " mins " + fullSecs-60*fullMins + " s";
	summaryTxt += "\nTotal of minimum distances recorded = " + lcf*totalMinDistPx + " " + unit;
	IJ.log(summaryTxt);
	beep(); wait(300); beep(); wait(300); beep();
	Dialog.create("Save options \(" + macroL + "\)");
		Dialog.addDirectory("Folder for saving work in progress:",defImagePath);
		Dialog.addCheckbox("Save image using filename below",true);
		Dialog.addFile("Image filename:",fileNameNE+"_NNSep.tif");
		Dialog.addCheckbox("Save Results using path below",true);
		Dialog.addFile("Results filename:",fileNameNE+"_Results_" + dateCode + ".csv");
		Dialog.addCheckbox("Save ROI set using path below",true);
		Dialog.addFile("ROI filename:",fileNameNE+"_ROIs_" + dateCode + ".zip");
	Dialog.show;
		saveDir = Dialog.getString();
		saveImage = Dialog.getCheckbox();
		imagePath = saveDir + Dialog.getString();
		saveResults = Dialog.getCheckbox();
		resultsPath = saveDir + Dialog.getString();
		saveROI = Dialog.getCheckbox();
		roiPath = saveDir + Dialog.getString();
	selectWindow(t);
	if (saveImage){
		getSet = verifiedGetSet("set",prefsNameKey+"LastRunImage",true,imagePath);
		if (getSet=="") IJ.log("Failed to save\n" + imagePath);
	}
	if (saveResults){
		getSet = verifiedGetSet("set",prefsNameKey+"LastRunResults",true,resultsPath);
		if (getSet=="") IJ.log("Failed to save\n" + resultsPath);
	}
	if(saveROI){
		getSet = verifiedGetSet("set",prefsNameKey+"lastRunROIs",true,roiPath);
		if (getSet=="") IJ.log("Failed to save\n" + roiPath);
	}
	if (roiManager("count")<=0) && tempROIpath!=""){
		getSet = verifiedGetSet("get",prefsNameKey+"tempROIs",true,"");
		if (getSet=="") IJ.log("Failed to restore\n" + tempROIpath);
		else getSet = verifiedGetSet("set",prefsNameKey+"lastRunROIs",true,roiPath);
		if (getSet=="") IJ.log("Failed to save\n" + roiPath);
	}
	memFlush(300); /* Applies 3 memory clearing commands from a function with 300 ms wait times */
	if(mDiagnostics) IJ.log("Final memory: " + IJ.freeMemory + "\n-----\n");
	restoreSettings();
	/*
		End of Add_NN_ROI_Min-Separation_to_Results macro
	*/
	/*
		( 8(|)	( 8(|)	ASC Functions	@@@@@:-)	@@@@@:-)
	*/
	function addImageToStack(stackName,baseImage) {
		run("Copy");
		selectWindow(stackName);
		run("Add Slice");
		run("Paste");
		selectWindow(baseImage);
	}
	function arrayToString(array,delimiter){
		/* 1st version April 2019 PJL
			v190722 Modified to handle zero length array
			v201215 += stopped working so this shortcut has been replaced */
		for (i=0; i<array.length; i++){
			if (i==0) string = "" + array[0];
			else  string = string + delimiter + array[i];
		}
		return string;
	}
	function checkForEdgeObjects(){
	/*	1st version v190725 */
		run("Select None");
		imageWidth = getWidth(); imageHeight = getHeight();
		makeRectangle(1, 1, imageWidth-2, imageHeight-2);
		run("Make Inverse");
		getStatistics(null, null, borderMin, borderMax);
		run("Select None");
		if (borderMin!=borderMax) edgeObjects = true;
		else edgeObjects = false;
		return edgeObjects;
	}
	function checkForRoiManager() {
		/* v161109 adds the return of the updated ROI count and also adds dialog if there are already entries just in case . .
			v180104 only asks about ROIs if there is a mismatch with the results
			v190628 adds option to import saved ROI set
			v210428	include thresholding if necessary and color check
			v211108 Uses radio-button group.
			NOTE: Requires ASC restoreExit function, which assumes that saveSettings has been run at the beginning of the macro
			v220706: Table friendly version
			v220816: Enforces non-inverted LUT as well as white background and fixes ROI-less analyze.  Adds more dialog labeling.
			v230126: Does not change foreground or background colors.
			v230130: Cosmetic improvements to dialog.
			*/
		functionL = "checkForRoiManager_v230126";
		nROIs = roiManager("count");
		nRes = nResults;
		tSize = Table.size;
		if (nRes==0 && tSize>0){
			oTableTitle = Table.title;
			renameTable = getBoolean("There is no Results table but " + oTableTitle + "has " +tSize+ "rows:", "Rename to Results", "No, I will take may chances");
			if (renameTable) {
				Table.rename(oTableTitle, "Results");
				nRes = nResults;
			}
		}
		if(nROIs==0 || nROIs!=nRes){
			Dialog.create("ROI mismatch options: " + functionL);
				Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are   " + nRes +"   results.\nThere are   " + nROIs + "   ROIs",12,"#782F40");
				mismatchOptions = newArray();
				if(nROIs==0) mismatchOptions = Array.concat(mismatchOptions,"Import a saved ROI list");
				else mismatchOptions = Array.concat(mismatchOptions,"Replace the current ROI list with a saved ROI list");
				if(nRes==0) mismatchOptions = Array.concat(mismatchOptions,"Import a Results Table \(csv\) file");
				else mismatchOptions = Array.concat(mismatchOptions,"Clear Results Table and import saved csv");
				mismatchOptions = Array.concat(mismatchOptions,"Clear ROI list and Results Table and reanalyze \(overrides above selections\)");
				if (!is("binary")) Dialog.addMessage("The active image is not binary, so it may require thresholding before analysis");
				mismatchOptions = Array.concat(mismatchOptions,"Get me out of here, I am having second thoughts . . .");
				Dialog.addRadioButtonGroup("How would you like to proceed:_____", mismatchOptions, lengthOf(mismatchOptions), 1, mismatchOptions[0]);
			Dialog.show();
				mOption = Dialog.getRadioButton();
				if (startsWith(mOption,"Sorry")) restoreExit("Sorry this did not work out for you.");
			if (startsWith(mOption,"Clear ROI list and Results Table and reanalyze")) {
				if (!is("binary")){
					if (is("grayscale") && bitDepth()>8){
						proceed = getBoolean(functionL + ": Image is grayscale but not 8-bit, convert it to 8-bit?", "Convert for thresholding", "Get me out of here");
						if (proceed) run("8-bit");
						else restoreExit(functionL + ": Goodbye, perhaps analyze first?");
					}
					if (bitDepth()==24){
						colorThreshold = getBoolean(functionL + ": Active image is RGB, so analysis requires thresholding", "Color Threshold", "Convert to 8-bit and threshold");
						if (colorThreshold) run("Color Threshold...");
						else run("8-bit");
					}
					if (!is("binary")){
						/* Quick-n-dirty threshold if not previously thresholded */
						getThreshold(t1,t2);
						if (t1==-1)  {
							run("Auto Threshold", "method=Default");
							run("Convert to Mask");
							if (is("Inverting LUT")) run("Invert LUT");
							if(getPixel(0,0)==0) run("Invert");
						}
					}
				}
				if (is("Inverting LUT"))  run("Invert LUT");
				/* Make sure black objects on white background for consistency */
				cornerPixels = newArray(getPixel(0, 0), getPixel(0, 1), getPixel(1, 0), getPixel(1, 1));
				Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
				if (cornerMax!=cornerMin) restoreExit("Problem with image border: Different pixel intensities at corners");
				/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
					i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
				if (cornerMean==0) run("Invert");
				if (isOpen("ROI Manager"))	roiManager("reset");
				if (isOpen("Results")) {
					selectWindow("Results");
					run("Close");
				}
				// run("Analyze Particles..."); /* Letting users select settings does not create ROIs  ¯\_(?)_/¯ */
				run("Analyze Particles...", "display clear include add");
				nROIs = roiManager("count");
				nRes = nResults;
				if (nResults!=roiManager("count"))
					restoreExit(functionL + ": Results \(" +nRes+ "\) and ROI Manager \(" +nROIs+ "\) counts still do not match!");
			}
			else {
				if (startsWith(mOption,"Import a saved ROI")) {
					if (isOpen("ROI Manager"))	roiManager("reset");
					msg = functionL + ": Import ROI set \(zip file\), click \"OK\" to continue to file chooser";
					showMessage(msg);
					pathROI = File.openDialog(functionL + ": Select an ROI file set to import");
                    roiManager("open", pathROI);
				}
				if (startsWith(mOption,"Import a Results")){
					if (isOpen("Results")) {
						selectWindow("Results");
						run("Close");
					}
					msg = functionL + ": Import Results Table: Click \"OK\" to continue to file chooser";
					showMessage(msg);
					open(File.openDialog(functionL + ": Select a Results Table to import"));
					Table.rename(Table.title, "Results");
				}
			}
		}
		nROIs = roiManager("count");
		nRes = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0 || nROIs!=nRes)
			restoreExit(functionL + ": Goodbye, there are " + nROIs + " ROIs and " + nRes + " results; your previous settings will be restored.");
		return roiManager("count"); /* Returns the new count of entries */
	}
	function checkForUnits() {  /* Generic version
		/* v161108 (adds inches to possible reasons for checking calibration)
		 v170914 Radio dialog with more information displayed
		 v200925 looks for pixels unit too; v210428 just adds function label */
		functionL = "checkForUnits_v210428";
		getPixelSize(unit, pixelWidth, pixelHeight);
		if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches" || unit=="pixels"){
			Dialog.create("Suspicious Units: " + functionL);
			rescaleChoices = newArray("Define new units for this image", "Use current scale", "Exit this macro");
			rescaleDialogLabel = "pixelHeight = "+pixelHeight+", pixelWidth = "+pixelWidth+", unit = "+unit+": what would you like to do?";
			Dialog.addRadioButtonGroup(rescaleDialogLabel, rescaleChoices, 3, 1, rescaleChoices[0]) ;
			Dialog.show();
			rescaleChoice = Dialog.getRadioButton;
			if (rescaleChoice==rescaleChoices[0]) run("Set Scale...");
			else if (rescaleChoice==rescaleChoices[2]) restoreExit("Goodbye");
		}
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
		/* v181002 reselects original image at end if open
		   v200925 uses "while" instead of if so it can also remove duplicates
		*/
		oIID = getImageID();
        while (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			close();
		}
		if (isOpen(oIID)) selectImage(oIID);
	}
	function createRandomIndexArray(arraylength){
		/* Based in https://imagej.nih.gov/ij/macros/examples/RandomizeArray.txt */
		randomArray = Array.getSequence(arraylength);
		n = randomArray.length;
		while (n > 1) {
		  k = n * random();     // 0 <= k < n.
		  n--;                  // n is now the last pertinent index;
		  temp = randomArray[n];  // swap array[n] with array[k] (does nothing if k==n).
		  randomArray[n] = randomArray[k];
		  randomArray[k] = temp;
		}
		return randomArray;
	}
	function createROIImage(newTitle,imageWidth,imageHeight,blackBackground,labelObjects,expandN,hollow) { /* blackBackground and labelObjects options are true-false */
		/* Creates a binary or ROI labeled image
			Requires restoreExit function
			v230130 1st "universal" version with label option and background options */
		batchMode = is("Batch Mode"); /* Store batch status mode before toggling */
		if (!batchMode) setBatchMode(true); /* Toggle batch mode on if previously off */
		labels = roiManager("count");
		if (labels==0) restoreExit("Sorry, this macro labels using ROI Manager objects, try the Landini plugin instead.");
		if (blackBackground) bG = "black";
		else bG = "white";
		maxInt = 65535;
		if (labelObjects){
			if (labels>65534) restoreExit("The labeling function is limited to 65536 objects");
			else if (labels<=253){
				newImage(newTitle, "8-bit " + bG, imageWidth, imageHeight, 1);
				maxInt = 255;
			}
			else newImage(newTitle, "16-bit " + bG, imageWidth,imageHeight, 1);
			statusMessage = "Creating 1 to " + labels + " intensity labeled inlines image";
		}
		else{
			newImage(newTitle, "8-bit " + bG, imageWidth, imageHeight, 1);
			maxInt = 255;
		}
		if (hollow && expandN==0) expandN = -1; /* I think you would expect hollow to still work even if without defined thickness */
		statusMessage = "Creating " + newTitle + " with " + labels;
		if (hollow) statusMessage += " hollow \(" + expandN + " pixels thick\)";
		statusMessage += " objects";
		if(labelObjects) statusMessage += " with ROI labels";
		if(blackBackground) statusMessage += ", on black background";
		else statusMessage += ", on white background";
		showStatus(statusMessage);
		for (i=0,labelValue=1; i<labels; i++,labelValue++) {
			showProgress(i, labels);
			roiManager("select", i);
			if (expandN<=0){
				if (labelObjects) run("Set...", "value=[labelValue]");
				else if (blackBackground) run("Set...", "value=[maxInt]");
				else run("Set...", "value=0");
				if (hollow){
					expandN = minOf(expandN,-1);
					run("Enlarge...", "enlarge=[expandN] pixel");
					if (blackBackground) run("Set...", "value=0");
					else run("Set...", "value=[maxInt]");
				}
			}
			else {
				if (expandN<0){
					run("Enlarge...", "enlarge=[expandN] pixel"); /* i.e. outer outLines */
					if (labelObjects) run("Set...", "value=[labelValue]");
					else if (blackBackground) run("Set...", "value=[maxInt]");
					else run("Set...", "value=0");
				}
				if (hollow){  /* I think you would expect hollow to still work even if without defined thickness */
					roiManager("select", i);
					if (blackBackground) run("Set...", "value=0");
					else run("Set...", "value=[maxInt]");
				}
			}
		}
		run("Select None");
		if (!labelObjects){
			run("Convert to Mask");
			if(is("Inverting LUT")) run("Invert LUT");
			if (blackBackground && getPixel(0, 0)!=0) run("Invert");/* For white BG Binary*/
			else if(!blackBackground && getPixel(0, 0)!=255) run("Invert");/* For black BG binary */
		}
		if(is("Inverting LUT")) run("Invert LUT");
		if (!batchMode) setBatchMode("exit and display");
	}
	function getDateCode() {
		/* v170823 */
		getDateAndTime(year, month, dayOfWeek, dayOfMonth, hour, minute, second, msec);
		month = month + 1; /* Month starts at zero, presumably to be used in array */
		if(month<10) monthStr = "0" + month;
		else monthStr = ""  + month;
		if (dayOfMonth<10) dayOfMonth = "0" + dayOfMonth;
		dateCodeUS = monthStr+dayOfMonth+substring(year,2);
		return dateCodeUS;
	}
  	function getFontChoiceList() {
		/*	v180723 first version
			v180828 Changed order of favorites
			v190108 Longer list of favorites
		*/
		systemFonts = getFontList();
		IJFonts = newArray("SansSerif", "Serif", "Monospaced");
		fontNameChoice = Array.concat(IJFonts,systemFonts);
		faveFontList = newArray("Your favorite fonts here", "Open Sans ExtraBold", "Fira Sans ExtraBold", "Noto Sans Black", "Arial Black", "Montserrat Black", "Lato Black", "Roboto Black", "Merriweather Black", "Alegreya Black", "Tahoma Bold", "Calibri Bold", "Helvetica", "SansSerif", "Calibri", "Roboto", "Tahoma", "Times New Roman Bold", "Times Bold", "Serif");
		faveFontListCheck = newArray(faveFontList.length);
		counter = 0;
		for (i=0; i<faveFontList.length; i++) {
			for (j=0; j<fontNameChoice.length; j++) {
				if (faveFontList[i] == fontNameChoice[j]) {
					faveFontListCheck[counter] = faveFontList[i];
					counter +=1;
					j = fontNameChoice.length;
				}
			}
		}
		faveFontListCheck = Array.trim(faveFontListCheck, counter);
		fontNameChoice = Array.concat(faveFontListCheck,fontNameChoice);
		return fontNameChoice;
	}
	function getResultsTableList() {
		/* simply returns array of open results tables
		v200723: 1st version
		v201207: Removed warning message */
		nonImageWindows = getList("window.titles");
		if (nonImageWindows.length>0){
			resultsWindows = newArray();
			for (i=0; i<nonImageWindows.length; i++){
				selectWindow(nonImageWindows[i]);
				if(getInfo("window.type")=="ResultsTable")
				resultsWindows = Array.concat(resultsWindows,nonImageWindows[i]);
			}
			return resultsWindows;
		}
		else return "";
	}
	function getTimeLeftTxt(startTime,startN,currentN,finishN){
		/* v230127: 1st version */
		secsToComplete = round((finishN-currentN) * (getTime()-startTime)/(1000 * (currentN-startN)));
		minsToComplete = floor(secsToComplete/60);
		secsToComplete -= minsToComplete*60;
		timeLeftTxt = "";
		if (minsToComplete>0) timeLeftTxt += "" + minsToComplete + " mins";
		if (secsToComplete>0) timeLeftTxt += " " + secsToComplete + " secs";
		return timeLeftTxt;
	}
	function indexOfArray(array,string,default) {
		/* v190423 Adds "default" parameter (use -1 for backwards compatibility). Returns only first found value */
		index = default;
		for (i=0; i<lengthOf(array); i++){
			if (array[i]==string) {
				index = i;
				i = lengthOf(array);
			}
		}
		return index;
	}
	function memFlush(waitTime) {
		run("Reset...", "reset=[Undo Buffer]");
		wait(waitTime);
		run("Reset...", "reset=[Locked Image]");
		wait(waitTime);
		call("java.lang.System.gc"); /* force a garbage collection */
		wait(waitTime);
	}
	function removeBlackEdgeObjects(){
	/*	Remove black edge objects without using Analyze Particles
	Peter J. Lee  National High Magnetic Field Laboratory
	1st version v190604
	v200102 Removed unnecessary print command.
	v230106 Does not require any plugins or other functions. Uses built-in macro functions for working with colors available in ImageJ 1.53h and later
	*/
		requires("1.53h");	
		originalFGCol = Color.foreground;
		cWidth = getWidth()+2; cHeight = getHeight()+2;
		run("Canvas Size...", "width=&cWidth height=&cHeight position=Center zero");
		Color.setForeground("white");
		floodFill(0, 0);
		Color.setForeground(originalFGCol);
		makeRectangle(1, 1, cWidth-2, cHeight-2);
		run("Crop");
		showStatus("Remove_Edge_Objects function complete");
	}
	function restoreExit(message){ /* Make a clean exit from a macro, restoring previous settings */
		/* v200305 1st version using memFlush function */
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		memFlush(200);
		exit(message);
	}
	function selectResultsWindow(){
		/* selects the Results window
			v200722: 1st version */
		nonImageWindows = getList("window.titles");
		resultsWindows = newArray();
		if (nonImageWindows.length!=0) {
			for (i=0; i<nonImageWindows.length; i++){
				selectWindow(nonImageWindows[i]);
				if(getInfo("window.type")=="ResultsTable")
					resultsWindows = Array.concat(resultsWindows,nonImageWindows[i]);
			}
		}
		if (resultsWindows.length>1){
			resultsWindows = Array.sort(resultsWindows); /* R for Results comes before S for Summary */
			Dialog.create("Select table for analysis: v200722");
			Dialog.addChoice("Choose Results Table: ",resultsWindows,resultsWindows[0]);
			Dialog.show();
			selectWindow(Dialog.getChoice());
		}
  	}
	function verifiedGetSet(setOrGet,key,openOrSave,optPath){
		/* (setOrGet,key,altPath) setOrGet should be "set" or "get",
		key is the full prefs key (the key should end in "Image", "Results", or "ROIs")
		openOrSave is true/false if false the function just returns the prefs key
		optPath is the alternative path for the call (could be just "" for get, needs to be the save path for set)
		v230131: 1st version    Peter J. Lee  Applied Superconductivity Center NHMFL FS
		*/
		setOrGet = toLowerCase(setOrGet);
		openImageN = nImages;
		success = false;
		if (setOrGet!="set" && setOrGet!="get") exit("Expecting 'set' or 'get', not " + setOrGet);
		else if (!endsWith(key,"ROIs") && !endsWith(key,"Results") && !endsWith(key,"Image")) exit("Expecting suffix of 'ROIs' or 'Results' or 'Image' not " + key);
		else if (setOrGet=="get"){
			restorePath = call("ij.Prefs.get", key, optPath);
			if (File.exists(restorePath)){
				if (File.length(restorePath)>0){
					if (!openOrSave) return restorePath;
					else if(endsWith(key,"ROIs")){
						nROIs = roiManager("count");
						if (nROIs>0){
							roiManager("reset");
							IJ.log("Previous " + nROIs + " ROIs replaced from: " + restorePath);
						}
						else IJ.log("ROIs restored from:\n" + restorePath);
						roiManager("open", restorePath);
						if (roiManager("count")>0)){
							call("ij.Prefs.set", key, restorePath);
							success = true;
						}
					}
					else if(endsWith(key,"Image")){
						open(restorePath);
						if(nImages>openImageN){
							IJ.log("Image restored from: " + restorePath);
							success = true;
						}
					}
					else if(endsWith(key,"Results")){
						File.open(restorePath);
						if(nResults>0){
							IJ.log("Results restored from: " + restorePath);
							success = true;
						}
					}
				}
			}
			if (success) return restorePath;
			else return "";				
		}
		/* should be 'set' from now on */
		else {
			saveSuccess = false;
			if(endsWith(key,"ROIs")){
				if(roiManager("count")>0){
					if (openOrSave) roiManager("save", optPath);
					if (File.exists(optPath)){
						if (File.length(optPath)>0) success = true;
					}
				}
			}
			else if(endsWith(key,"Results")){
				if(nResults>0){
					if (openOrSave) saveAs("Results", optPath);
					if (File.exists(optPath){
						if (File.length(optPath)>0) success = true;
					}
				}
			}
			else if (nImages>0){
				if (openOrSave) save(optPath);
				if (File.exists(optPath)){
					if (File.length(optPath)>0)	success = true;
				}
			}
			if (success) return optPath;
			else return "";
		}
		/* end of verifiedGetSet */
	}
		
	/* modified BAR color functions */
	
	function getColorArrayFromColorName(colorName) {
		/* v180828 added Fluorescent Colors
		   v181017-8 added off-white and off-black for use in gif transparency and also added safe exit if no color match found
		   v191211 added Cyan
		   v211022 all names lower-case, all spaces to underscores v220225 Added more hash value comments as a reference v220706 restores missing magenta
		   REQUIRES restoreExit function.  57 Colors v230130 Added more descriptions and modified order
		*/
		if (colorName == "white") cA = newArray(255,255,255);
		else if (colorName == "black") cA = newArray(0,0,0);
		else if (colorName == "off-white") cA = newArray(245,245,245);
		else if (colorName == "off-black") cA = newArray(10,10,10);
		else if (colorName == "light_gray") cA = newArray(200,200,200);
		else if (colorName == "gray") cA = newArray(127,127,127);
		else if (colorName == "dark_gray") cA = newArray(51,51,51);
		else if (colorName == "off-black") cA = newArray(10,10,10);
		else if (colorName == "light_gray") cA = newArray(200,200,200);
		else if (colorName == "gray") cA = newArray(127,127,127);
		else if (colorName == "dark_gray") cA = newArray(51,51,51);
		else if (colorName == "red") cA = newArray(255,0,0);
		else if (colorName == "green") cA = newArray(0,255,0); /* #00FF00 AKA Lime green */
		else if (colorName == "blue") cA = newArray(0,0,255);
		else if (colorName == "cyan") cA = newArray(0, 255, 255);
		else if (colorName == "yellow") cA = newArray(255,255,0);
		else if (colorName == "magenta") cA = newArray(255,0,255); /* #FF00FF */
		else if (colorName == "pink") cA = newArray(255, 192, 203);
		else if (colorName == "violet") cA = newArray(127,0,255);
		else if (colorName == "orange") cA = newArray(255, 165, 0);
		else if (colorName == "garnet") cA = newArray(120,47,64); /* #782F40 */
		else if (colorName == "gold") cA = newArray(206,184,136); /* #CEB888 */
		else if (colorName == "aqua_modern") cA = newArray(75,172,198); /* #4bacc6 AKA "Viking" aqua */
		else if (colorName == "blue_accent_modern") cA = newArray(79,129,189); /* #4f81bd */
		else if (colorName == "blue_dark_modern") cA = newArray(31,73,125); /* #1F497D */
		else if (colorName == "blue_honolulu") cA = newArray(0,118,182); /* Honolulu Blue #30076B6 */
		else if (colorName == "blue_modern") cA = newArray(58,93,174); /* #3a5dae */
		else if (colorName == "gray_modern") cA = newArray(83,86,90); /* bright gray #53565A */
		else if (colorName == "green_dark_modern") cA = newArray(121,133,65); /* Wasabi #798541 */
		else if (colorName == "green_modern") cA = newArray(155,187,89); /* #9bbb59 AKA "Chelsea Cucumber" */
		else if (colorName == "green_modern_accent") cA = newArray(214,228,187); /* #D6E4BB AKA "Gin" */
		else if (colorName == "green_spring_accent") cA = newArray(0,255,102); /* #00FF66 AKA "Spring Green" */
		else if (colorName == "orange_modern") cA = newArray(247,150,70); /* #f79646 tan hide, light orange */
		else if (colorName == "pink_modern") cA = newArray(255,105,180); /* hot pink #ff69b4 */
		else if (colorName == "purple_modern") cA = newArray(128,100,162); /* blue-magenta, purple paradise #8064A2 */
		else if (colorName == "jazzberry_jam") cA = newArray(165,11,94);
		else if (colorName == "red_n_modern") cA = newArray(227,24,55);
		else if (colorName == "red_modern") cA = newArray(192,80,77);
		else if (colorName == "tan_modern") cA = newArray(238,236,225);
		else if (colorName == "violet_modern") cA = newArray(76,65,132);
		else if (colorName == "yellow_modern") cA = newArray(247,238,69);
		/* Fluorescent Colors https://www.w3schools.com/colors/colors_crayola.asp */
		else if (colorName == "radical_red") cA = newArray(255,53,94);			/* #FF355E */
		else if (colorName == "wild_watermelon") cA = newArray(253,91,120);		/* #FD5B78 */
		else if (colorName == "shocking_pink") cA = newArray(255,110,255);		/* #FF6EFF Ultra Pink */
		else if (colorName == "razzle_dazzle_rose") cA = newArray(238,52,210); 	/* #EE34D2 */
		else if (colorName == "hot_magenta") cA = newArray(255,0,204);			/* #FF00CC AKA Purple Pizzazz */
		else if (colorName == "outrageous_orange") cA = newArray(255,96,55);	/* #FF6037 */
		else if (colorName == "supernova_orange") cA = newArray(255,191,63);	/* FFBF3F Supernova Neon Orange*/
		else if (colorName == "sunglow") cA = newArray(255,204,51); 			/* #FFCC33 */
		else if (colorName == "neon_carrot") cA = newArray(255,153,51);			/* #FF9933 */
		else if (colorName == "atomic_tangerine") cA = newArray(255,153,102);	/* #FF9966 */
		else if (colorName == "laser_lemon") cA = newArray(255,255,102); 		/* #FFFF66 "Unmellow Yellow" */
		else if (colorName == "electric_lime") cA = newArray(204,255,0); 		/* #CCFF00 */
		else if (colorName == "screamin'_green") cA = newArray(102,255,102); 	/* #66FF66 */
		else if (colorName == "magic_mint") cA = newArray(170,240,209); 		/* #AAF0D1 */
		else if (colorName == "blizzard_blue") cA = newArray(80,191,230); 		/* #50BFE6 Malibu */
		else if (colorName == "dodger_blue") cA = newArray(9,159,255);			/* #099FFF Dodger Neon Blue */
		else restoreExit("No color match to " + colorName);
		return cA;
	}
	function setColorFromColorName(colorName) {
		colorArray = getColorArrayFromColorName(colorName);
		setColor(colorArray[0], colorArray[1], colorArray[2]);
	}