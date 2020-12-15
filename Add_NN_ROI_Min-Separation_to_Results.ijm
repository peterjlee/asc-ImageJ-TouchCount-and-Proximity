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
*/
	macroL = "Add_NN_ROI_Min-Separation_to_Results_v201215";
	requires("1.47r"); /* not sure of the actual latest working version but 1.45 definitely doesn't work */
	memFlush(200); /* This macro needs all the help it can get */
	saveSettings(); /* To restore settings at the end */
	setOption("ExpandableArrays", true); /* In ImageJ 1.53g and later, arrays automatically expand in size as needed */
	/*   ('.')  ('.')   Black objects on white background settings   ('.')   ('.')   */	
	/* Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	run("Appearance...", " "); if(is("Inverting LUT")) run("Invert LUT"); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background) http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	t = getTitle();
	binaryCheck(t);
	if (removeEdgeObjects() && roiManager("count")!=0) roiManager("reset"); /* macro does not make much sense if there are edge objects but perhaps they are not included in ROI list (you can cancel out of this). if the object removal routine is run it will also reset the ROI Manager list if it already contains entries */
	checkForRoiManager();
	rOIs = roiManager("count");
	fCycles = floor(rOIs/10); /* How frequently to check memory usage */
	run("Options...", "count=1 do=Nothing"); /* The binary count setting is set to "1" for consistent outlines */
	imageWidth = getWidth();
	imageHeight = getHeight();
	dimProd = imageWidth*imageHeight;
	dimSum = imageWidth+imageHeight;
	checkForUnits();
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2; /* ---> add here the side size of 1 pixel in the new calibrated units (e.g. lcf=5, if 1 pixels is 5mm) <--- */
	/* create the dialog prompt */
	selectResultsWindow(); /* allows you to choose from multiple windows */
	Array.getStatistics(Table.getColumn("Perim."), minPerim, maxPerim, meanPerim, null) ;
	subSamD = minOf(floor(minPerim/(20*lcf)),floor(dimProd/500000));
	totalPPx = round(rOIs * meanPerim/lcf);
	maxPerimPx = maxPerim/lcf;
	dLW = maxOf(1,round(imageWidth/1024)); /* default line width */
	leq = fromCharCode(0x2264);
	prefsNameKey = "asc.NN.ROI.sep.Prefs.";
	Dialog.create("Options for: " + macroL);
		Dialog.addNumber("No. of object distance sets \("+leq+"6\) to be added to Results Table:", minOf(6,rOIs-1), 0, 6,"of " + rOIs + " ROIs");
		Dialog.addNumber("No. of adjacent objects to included in search:", minOf(12,rOIs-1), 0, 6,"adjacent ROIs");
		Dialog.addMessage("This brute force approach is a little slow but it can be\nsped up by sub-sampling the perimeter points:");
		Dialog.addNumber("Sub-sample of origin outline pixels:", 0, 0, 3,"pixels skipped");
		Dialog.addNumber("Sub-sample of nearest neighbor perimeter pixels:", subSamD, 0, 3,"pixels skipped");
		Dialog.addCheckbox("Draw Overlay lines at proximity positions",true);
	Dialog.show;	
		maxTableObjects = minOf(rOIs-1,Dialog.getNumber); /* put a limit of how many adjacent filaments to report */
		maxNNOs = minOf(rOIs-1,Dialog.getNumber);
		subSamO = Dialog.getNumber();
		subSamD = Dialog.getNumber();
		drawConnector = Dialog.getCheckbox();

	if (drawConnector){
		colorChoiceMono = newArray("white", "black", "off-white", "off-black", "light_gray", "gray", "dark_gray");
		colorChoiceStd = newArray("red", "cyan", "pink","green", "blue", "yellow", "orange", "magenta");
		colorChoiceMod = newArray("garnet", "gold", "aqua_modern", "blue_accent_modern", "blue_dark_modern", "blue_modern", "gray_modern", "green_dark_modern", "green_modern", "orange_modern", "pink_modern", "purple_modern");
		colorChoiceNeon = newArray("jazzberry_jam", "red_N_modern", "red_modern", "tan_modern", "violet_modern", "yellow_modern", "Radical Red", "Wild Watermelon", "Outrageous Orange", "Atomic Tangerine", "Neon Carrot", "Sunglow", "Laser Lemon", "Electric Lime", "Screamin' Green", "Magic Mint", "Blizzard Blue", "Shocking Pink", "Razzle Dazzle Rose", "Hot Magenta");
		colorChoice = Array.concat(colorChoiceMono,colorChoiceStd,colorChoiceMod,colorChoiceNeon);
		defaultColorOrder = Array.trim(colorChoiceStd,6);
		prefsDelimiter = "|";
		colorString = call("ij.Prefs.get", prefsNameKey+"LineColors","red|cyan|pink|green|blue|yellow");
		colorPrefs = split(colorString, prefsDelimiter);
		colorPrefs = Array.concat(colorPrefs,defaultColorOrder);
		defThickns = newArray(12);
		Array.fill(defThickns, dLW);
		defThicknString = arrayToString(defThickns,prefsDelimiter);
		thicknString = call("ij.Prefs.get", prefsNameKey+"LineThickness",defThicknString);
		thicknString = replace(thicknString, NaN, dLW);
		thicknPrefs = split(parseInt(thicknString), prefsDelimiter);
		thicknPrefs = Array.concat(thicknPrefs,defThickns);
		Dialog.create("Connector Overlay Line Drawing Options");
			maxLines = minOf(maxTableObjects,6);
			for(lineP=0;lineP<maxLines; lineP++){
				Dialog.addChoice("Line color for distance " + lineP+1, colorChoice, colorPrefs[lineP]);
				Dialog.addNumber("Line width for distance " + lineP+1, thicknPrefs[lineP], 0, 3,"pixels");
			}
			Dialog.addCheckbox("Remove previous overlays?",true);
			Dialog.addCheckbox("Create Animation Line Stack?",false);
			Dialog.addCheckbox("Create Legend?",false);
		Dialog.show;
			lineColors = newArray(maxLines);
			lineThickness = newArray(maxLines);
			for(lineN=0; lineN<maxLines; lineN++){
				lineColors[lineN] = Dialog.getChoice;
				lineThickness[lineN] = Dialog.getNumber;
			}
			if(Dialog.getCheckbox())run("Remove Overlay");
			animStack = Dialog.getCheckbox;
			createLegend = Dialog.getCheckbox;
		maxLines = minOf(maxTableObjects,6);
		colorsString = arrayToString(lineColors,prefsDelimiter);
		thicknessString = arrayToString(lineThickness,prefsDelimiter);
		call("ij.Prefs.set", prefsNameKey+"LineColors", colorsString);
		call("ij.Prefs.set", prefsNameKey+"LineThickness", thicknessString);
	}
	start = getTime();
	setBatchMode(true);
	IJ.log("-----\n\n");
	IJ.log("6 Object Separation macro");
	IJ.log("Macro path: " + getInfo("macro.filepath"));
	IJ.log("Image used for count: " + t);
	IJ.log("Original magnification scale factor used = " + lcf + " with units: " + unit);
	IJ.log("Maximum object separations to be added to table = " + maxTableObjects);
	if (drawConnector){
		if (animStack) {
			tA = "Separation Line Animation Stack";
			run("Duplicate...", "title=[Separation Line Animation Stack]");
			run("RGB Color");
		}
	}
	createROILabeledImage(t,"Labeled");		/* now create labeled image using ROIs */
	selectWindow(t);
	/* Create Inline (perimeter pixels within object) of Perimeter image for all objects */
	run("Duplicate...", "title=Inline");
	run("Outline");
	/* Arrays containing all inLine pixel coordinates and ROI-mapped intensities - with optional sub-sampling */
	allInlinePxXs = newArray(0);
	allInlinePxYs = newArray(0);
	bgI = getPixel(0, 0); /* Determine background intensity as corner pixel */
	oPxls = 0; /* Counter for outline/inline pixels */
	/* Get all perimeter coordinates */
	for (iC=0; iC<imageWidth; iC++){
		showProgress(iC, imageWidth);
		showStatus("Acquiring all perimeter coordinates");
		for (jC=0; jC<imageHeight; jC++){
			pixelI = getPixel(iC, jC);
			if(pixelI!=bgI) {
				allInlinePxXs[oPxls] = iC;
				allInlinePxYs[oPxls] = jC;
				oPxls += 1;
			}
		jC += subSamD;
		}
	iC += subSamD;
	}
	IJ.log("Total perimeter pixels = " + totalPPx);
	IJ.log("Total perimeter coordinate sets = " + oPxls);
	closeImageByTitle("Inline");
	allInlinePxROIs = newArray(0);
	selectWindow("Labeled");
	/* get map ROI number */
	for (mapi=0; mapi<oPxls; mapi++){
		showProgress(mapi, oPxls);
		showStatus("Acquiring all map IDs");
		allInlinePxROIs[mapi] = getPixel(allInlinePxXs[mapi], allInlinePxYs[mapi]);
	}
	closeImageByTitle("Labeled");
	selectWindow(t);
	oCXs = Table.getColumn("X");
	oCYs = Table.getColumn("Y");
	oCDSqs = newArray(0);
	flushCount = 0;
	for (oROI=0; oROI<rOIs; oROI++){
		oCDSqs = newArray(0);
		showProgress(oROI, rOIs);
		showStatus("!Looping through "+ oROI + " of all " + rOIs);
		/* Create set of true ROI outline coordinates */
		newImage("ROIOutline", "8-bit black", imageWidth, imageHeight, 1);
		roiManager("Select", oROI);
		run("Clear", "slice");
		Roi.getBounds(xMin, yMin, roiWidth, roiHeight);
		outlinePxXs = newArray(0);
		outlinePxYs = newArray(0);
		xMin -= 1;	yMin -= 1; /* Adjust bounds for Outline */
		xMax = xMin + roiWidth + 2;
		yMax = yMin + roiHeight + 2;
		run("Select None");
		run("Outline");
		roiManager("Select", oROI);
		run("Enlarge...", "enlarge=1");
		run("Clear Outside"); /* Removes outline of image border */
		run("Select None");
		bgI = getPixel(0, 0);
		rPxls = 0;
		for (iM=xMin; iM<xMax; iM++){
			for (jM=yMin; jM<=yMax; jM++){
				pixelI = getPixel(iM, jM);
				if(pixelI != bgI) {
					outlinePxXs[rPxls] = iM;
					outlinePxYs[rPxls] = jM;
					rPxls += 1;
				}
			jM += subSamO;
			}
		iM += subSamO;
		}
		closeImageByTitle("ROIOutline");
		/* End of Outline coordinate set creation */
		selectWindow(t);
		/* Filter Inline destination coordinate set so that it only includes adjacent objects */
			/* First create a list of the distances to all the other ROI centers */
		for(iO=0; iO<rOIs; iO++){
			if (iO!=oROI)	oCDSqs[iO] = pow(oCXs[oROI]-oCXs[iO],2) + pow(oCYs[oROI]-oCYs[iO],2);
			else oCDSqs[iO] = dimProd; /* just something large enough to eliminate oROI from the sort */
		}
		nnOs = Array.rankPositions(oCDSqs); /* sort list of other ROIs by center-center distance-squared */
		/* Filter coordinate arrays so they only include nearest ROIs limited by dialog option creating new filter arrays */
		allInlinePxXsF = newArray(0);
		allInlinePxYsF = newArray(0);
		allInlinePxROIsF = newArray(0);
		oPxlsF = 0;
		for (n=0; n<maxNNOs; n++){
			for (f=0; f<oPxls; f++){
				if (allInlinePxROIs[f]==nnOs[n]) {
					allInlinePxXsF[oPxlsF] = allInlinePxXs[f];
					allInlinePxYsF[oPxlsF] = allInlinePxYs[f];
					allInlinePxROIsF[oPxlsF] = nnOs[n];
					oPxlsF += 1;
				}
			}
		}		
		/* Create or reset distance arrays for other objects */
		minDSqs = newArray(0);
		minDROI = newArray(0);
		minXs = newArray(0);
		minYs = newArray(0);
		minXOs = newArray(0);
		minYOs = newArray(0);
		/* For each ROI outline point find the min dist etc. to every inLine coordinate of the other ROIs */
		for (dROI=0; dROI<maxNNOs; dROI++){
			/* Find nearest in-line coordinate for every destination ROI */
			minDSqs[dROI] = dimProd; /* this should be greater than the largest distSq */
			for (rPx=0; rPx<rPxls; rPx++){ /* for all originating ROI outline pix */
				x1 = outlinePxXs[rPx];
				y1 = outlinePxYs[rPx];
				for (dROIpx=0; dROIpx<oPxlsF; dROIpx++){  /* for all inLine perimeter pixels */
					if(allInlinePxROIsF[dROIpx]==nnOs[dROI]) { /* skip all except destination ROI */
						x2 = allInlinePxXsF[dROIpx];
						y2 = allInlinePxYsF[dROIpx];
						distSq = pow(x1-x2,2) + pow(y1-y2,2); /* note this this the sqrt is not applied until the result is determined for the table */
						if (distSq < minDSqs[dROI]){
							minDSqs[dROI] = distSq;
							minXs[dROI] = x2;
							minYs[dROI] = y2;
							minXOs[dROI] = x1;
							minYOs[dROI] = y1;
							minDROI[dROI] = nnOs[dROI];
						}
					}
				}
			}
		}
		distIDRank = Array.rankPositions(minDSqs);
		for (n=0; n<maxTableObjects; n++){
			distROI = distIDRank[n];
			setResult("MinSepROI"+(n+1), oROI, minDROI[distROI]);
			minSep = sqrt(minDSqs[distROI]);
			setResult("MinSepROI"+(n+1)+"\(px\)", oROI, minSep);
			if (lcf!=1) setResult("MinSepROI"+(n+1)+"\("+unit+"\)", oROI, lcf*minSep);
			setResult("MinSepThisROIx"+(n+1), oROI, minXOs[distROI]);	
			setResult("MinSepThisROIy"+(n+1), oROI, minYOs[distROI]);
			setResult("MinSepNNROIx"+(n+1), oROI, minXs[distROI]);	
			setResult("MinSepNNROIy"+(n+1), oROI, minYs[distROI]);
			if (drawConnector){
				if(n<maxLines){
					if (animStack) newImage("Animation Frame", "8-bit white", imageWidth, imageHeight, 1);
					setLineWidth(lineThickness[n]);
					setColorFromColorName(lineColors[n]);
					Overlay.drawLine(minXOs[distROI], minYOs[distROI], minXs[distROI], minYs[distROI]);
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
		flushCount += 1;
		if (flushCount==fCycles) {
			updateResults();
			mC = parseInt(IJ.currentMemory());
			mX = parseInt(IJ.maxMemory());
			mCP = mC*(100/mX);
			if (mCP>90) {
				keepGoing = getBoolean(mCP + "% of IJ memory has been used, do you want to continue", "Yes", "No");
				if (!keepGoing) restoreExit("ImageJ may need restart to free memory. Then try fewer ROIs");
			}
			memFlush(200); /* Applies 3 memory clearing commands from a function with "fWait"" wait times */
			flushCount = 0;
		}
	}
	if (createLegend){
		closeImageByTitle("Legend"); /* Close previous legend */
		fontSize = maxOf(14,round(dimSum/60));
		fontNameChoice = getFontChoiceList();
		iFN = indexOfArray(fontNameChoice, call("ij.Prefs.get", "asc.legend.font.name",fontNameChoice[0]),0);
		fontStyleChoice = newArray("bold", "italic", "bold italic", "unstyled");
		iFS = indexOfArray(fontStyleChoice, call("ij.Prefs.get", "asc.legend.font.style",fontStyleChoice[0]),0);
		Dialog.create("Legend Options");
			Dialog.addNumber("Font Size", fontSize, 0,3,"pixels");
			Dialog.addChoice("Font name:", fontNameChoice, fontNameChoice[iFN]);
			Dialog.addChoice("Font style*:", fontStyleChoice, fontStyleChoice[iFS]);
			Dialog.addRadioButtonGroup("Legend Size: Fits Image", newArray("Height", "Width"),1,2,"Width");
			Dialog.addRadioButtonGroup("Add to image:", newArray("No", "Right/Top", "Left/Bottom"),3,1,"Left/Bottom");
			Dialog.addMessage("Combining the legend with the image creates a new\nflat combination image and closes the legend window.");
		Dialog.show;
			fontSize = Dialog.getNumber;
			fontName = Dialog.getChoice;
			fontStyle = Dialog.getChoice;
			legendFit = Dialog.getRadioButton;
			legendLoc = Dialog.getRadioButton;	
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
	updateResults();
	Overlay.show;
	setBatchMode("exit & display"); /* exit batch mode */
	IJ.log("Run time = " + (getTime()-start)/1000 + "s");
	IJ.log("-----\n");
	restoreSettings();
	run("Select None");
	showStatus("!Separation Macro Finished: " + roiManager("count") + " objects analyzed in " + (getTime()-start)/1000 + "s.");
	beep(); wait(300); beep(); wait(300); beep();
	memFlush(300); /* Applies 3 memory clearing commands from a function with 300 ms wait times */
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
	function binaryCheck(windowTitle) { /* For black objects on a white background */
		/* v180601 added choice to invert or not 
		v180907 added choice to revert to the true LUT, changed border pixel check to array stats
		v190725 Changed to make binary
		*/
		selectWindow(windowTitle);
		if (!is("binary")) run("8-bit");
		/* Quick-n-dirty threshold if not previously thresholded */
		getThreshold(t1,t2); 
		if (t1==-1)  {
			run("8-bit");
			run("Auto Threshold", "method=Default");
			setOption("BlackBackground", false);
			run("Make Binary");
		}
		if (is("Inverting LUT"))  {
			trueLUT = getBoolean("The LUT appears to be inverted, do you want the true LUT?", "Yes Please", "No Thanks");
			if (trueLUT) run("Invert LUT");
		}
		/* Make sure black objects on white background for consistency */
		cornerPixels = newArray(getPixel(0, 0), getPixel(0, 1), getPixel(1, 0), getPixel(1, 1));
		Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
		if (cornerMax!=cornerMin) restoreExit("Problem with image border: Different pixel intensities at corners");
		/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
		if (cornerMean==0) {
			inversion = getBoolean("The background appears to have intensity zero, do you want the intensities inverted?", "Yes Please", "No Thanks");
			if (inversion) run("Invert"); 
		}
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
	function checkForPlugin(pluginName) {
		/* v161102 changed to true-false
			v180831 some cleanup */
		var pluginCheck = false, subFolderCount = 0;
		if (getDirectory("plugins") == "") restoreExit("Failure to find any plugins!");
		else pluginDir = getDirectory("plugins");
		if (!endsWith(pluginName, ".jar")) pluginName = pluginName + ".jar";
		if (File.exists(pluginDir + pluginName)) {
				pluginCheck = true;
				showStatus(pluginName + "found in: "  + pluginDir);
		}
		else {
			pluginList = getFileList(pluginDir);
			subFolderList = newArray(lengthOf(pluginList));
			for (i=0; i<lengthOf(pluginList); i++) {
				if (endsWith(pluginList[i], "/")) {
					subFolderList[subFolderCount] = pluginList[i];
					subFolderCount += 1;
				}
			}
			subFolderList = Array.trim(subFolderList, subFolderCount);
			for (i=0; i<lengthOf(subFolderList); i++) {
				if (File.exists(pluginDir + subFolderList[i] +  "\\" + pluginName)) {
					pluginCheck = true;
					showStatus(pluginName + " found in: " + pluginDir + subFolderList[i]);
					i = lengthOf(subFolderList);
				}
			}
		}
		return pluginCheck;
	}
	function checkForRoiManager() {
		/* v161109 adds the return of the updated ROI count and also adds dialog if there are already entries just in case . .
			v180104 only asks about ROIs if there is a mismatch with the results
			v190628 adds option to import saved ROI set */
		nROIs = roiManager("count");
		nRes = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0 || nROIs!=nRes){
			Dialog.create("ROI options");
				Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are   " + nRes +"   results.\nThere are   " + nROIs +"   ROIs.\nDo you want to:");
				if(nROIs==0) Dialog.addCheckbox("Import a saved ROI list",false);
				else Dialog.addCheckbox("Replace the current ROI list with a saved ROI list",false);
				if(nRes==0) Dialog.addCheckbox("Import a Results Table \(csv\) file",false);
				else Dialog.addCheckbox("Clear Results Table and import saved csv",false);
				Dialog.addCheckbox("Clear ROI list and Results Table and reanalyze \(overrides above selections\)",true);
				Dialog.addCheckbox("Get me out of here, I am having second thoughts . . .",false);
			Dialog.show();
				importROI = Dialog.getCheckbox;
				importResults = Dialog.getCheckbox;
				runAnalyze = Dialog.getCheckbox;
				if (Dialog.getCheckbox) restoreExit("Sorry this did not work out for you.");
			if (runAnalyze) {
				if (isOpen("ROI Manager"))	roiManager("reset");
				setOption("BlackBackground", false);
				if (isOpen("Results")) {
					selectWindow("Results");
					run("Close");
				}
				run("Analyze Particles..."); /* Let user select settings */
				if (nResults!=roiManager("count"))
					restoreExit("Results and ROI Manager counts do not match!");
			}
			else {
				if (importROI) {
					if (isOpen("ROI Manager"))	roiManager("reset");
					msg = "Import ROI set \(zip file\), click \"OK\" to continue to file chooser";
					showMessage(msg);
					roiManager("Open", "");
				}
				if (importResults){
					if (isOpen("Results")) {
						selectWindow("Results");
						run("Close");
					}
					msg = "Import Results Table, click \"OK\" to continue to file chooser";
					showMessage(msg);
					open("");
					Table.rename(Table.title, "Results");
				}
			}
		}
		nROIs = roiManager("count");
		nRes = nResults; /* Used to check for ROIs:Results mismatch */
		if(nROIs==0 || nROIs!=nRes)
			restoreExit("Goodbye, your previous setting will be restored.");
		return roiManager("count"); /* Returns the new count of entries */
	}
	function checkForUnits() {  /* Generic version 
		/* v161108 (adds inches to possible reasons for checking calibration)
		 v170914 Radio dialog with more information displayed */
		getPixelSize(unit, pixelWidth, pixelHeight);
		if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches"){
			Dialog.create("Suspicious Units");
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
		/* v181002 reselects original image at end if open */
		oIID = getImageID();
        if (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			close();
		}
		if (isOpen(oIID)) selectImage(oIID);
	}
	function createROILabeledImage(originalImage,labelName) {
		/* 1st version variant that uses white image so label can start at zero */
		labels = roiManager("count"); /* ONLY this method of ROI counting returns "0" when there is no manager open */
		if (labels==0) restoreExit("Sorry, this macro labels using ROI Manager objects, try the Gabriel Landini plugin instead.");
		selectWindow(originalImage);
		run("Duplicate...", "title="+labelName);
		run("Convert to Mask");
		if(getPixel(0, 0)==0) run("Invert");/* Want black objects */
		if (labels>65536) run("32-bit"); /* hopefully no more than 4294967295! */
		else if (labels>=255) run("16-bit");
		for (i=0 ; i<labels; i++) {
			roiManager("select", i);
			run("Add...", "value=[i]");
			if (nResults==labels) setResult("Label\(Int\)", i, i);
		}
		run("Select None");
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
	function removeEdgeObjects(){
	/*	Remove black edge objects without using Analyze Particles
	Peter J. Lee  National High Magnetic Field Laboratory
	Requires:
		The versatile wand tool: https://imagej.nih.gov/ij/plugins/versatile-wand-tool/index.html by Michael Schmid as built in wand does not select edge objects
		checkForEdgeObjects function
	Optional: morphology_collection.jar
	1st version v190604
	v190605 This version uses Gabriel Landini's morphology plugin if available
	v190725 Checks for edges first and then returns "true" if edge objects removed
	v200102 Removed unnecessary print command.
	*/
		if (checkForEdgeObjects()) { /* requires checkForEdgeObjectsFunction */
			if (checkForPlugin("morphology_collection.jar")) run("BinaryKillBorders ", "top right bottom left");
			else {
				if (!checkForPlugin("Versatile_Wand_Tool.java") && !checkForPlugin("versatile_wand_tool.jar") && !checkForPlugin("Versatile_Wand_Tool.jar")) restoreExit("Versatile wand tool required");
				run("Select None");
				originalBGCol = getValue("color.background");
				cWidth = getWidth()+2; cHeight = getHeight()+2;
				run("Canvas Size...", "width=&cWidth height=&cHeight position=Center");
				setColor("black");
				drawRect(0, 0, cWidth, cHeight);
				call("Versatile_Wand_Tool.doWand", 0, 0, 0.0, 0.0, 0.0, "8-connected");
				run("Colors...", "background=white");
				run("Clear", "slice");
				setBackgroundColor(originalBGCol); /* Return background to original color */
				makeRectangle(1, 1, cWidth-2, cHeight-2);
				run("Crop");
			}
			showStatus("Remove_Edge_Objects function complete");
			removeObjects = true;
		}
		else removeObjects = false;
		return removeObjects;
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
	function getColorArrayFromColorName(colorName) {
		/* v180828 added Fluorescent Colors
		   v181017-8 added off-white and off-black for use in gif transparency and also added safe exit if no color match found
		   v191211 added cyan
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
		else if (colorName == "pink") cA = newArray(255, 192, 203);
		else if (colorName == "green") cA = newArray(0,255,0); /* #00FF00 AKA Lime green */
		else if (colorName == "blue") cA = newArray(0,0,255);
		else if (colorName == "yellow") cA = newArray(255,255,0);
		else if (colorName == "orange") cA = newArray(255, 165, 0);
		else if (colorName == "cyan") cA = newArray(0, 255, 255);
		else if (colorName == "garnet") cA = newArray(120,47,64);
		else if (colorName == "gold") cA = newArray(206,184,136);
		else if (colorName == "aqua_modern") cA = newArray(75,172,198); /* #4bacc6 AKA "Viking" aqua */
		else if (colorName == "blue_accent_modern") cA = newArray(79,129,189); /* #4f81bd */
		else if (colorName == "blue_dark_modern") cA = newArray(31,73,125);
		else if (colorName == "blue_modern") cA = newArray(58,93,174); /* #3a5dae */
		else if (colorName == "gray_modern") cA = newArray(83,86,90);
		else if (colorName == "green_dark_modern") cA = newArray(121,133,65);
		else if (colorName == "green_modern") cA = newArray(155,187,89); /* #9bbb59 AKA "Chelsea Cucumber" */
		else if (colorName == "green_modern_accent") cA = newArray(214,228,187); /* #D6E4BB AKA "Gin" */
		else if (colorName == "green_spring_accent") cA = newArray(0,255,102); /* #00FF66 AKA "Spring Green" */
		else if (colorName == "orange_modern") cA = newArray(247,150,70);
		else if (colorName == "pink_modern") cA = newArray(255,105,180);
		else if (colorName == "purple_modern") cA = newArray(128,100,162);
		else if (colorName == "jazzberry_jam") cA = newArray(165,11,94);
		else if (colorName == "red_N_modern") cA = newArray(227,24,55);
		else if (colorName == "red_modern") cA = newArray(192,80,77);
		else if (colorName == "tan_modern") cA = newArray(238,236,225);
		else if (colorName == "violet_modern") cA = newArray(76,65,132);
		else if (colorName == "yellow_modern") cA = newArray(247,238,69);
		/* Fluorescent Colors https://www.w3schools.com/colors/colors_crayola.asp */
		else if (colorName == "Radical Red") cA = newArray(255,53,94);			/* #FF355E */
		else if (colorName == "Wild Watermelon") cA = newArray(253,91,120);		/* #FD5B78 */
		else if (colorName == "Outrageous Orange") cA = newArray(255,96,55);	/* #FF6037 */
		else if (colorName == "Supernova Orange") cA = newArray(255,191,63);	/* FFBF3F Supernova Neon Orange*/
		else if (colorName == "Atomic Tangerine") cA = newArray(255,153,102);	/* #FF9966 */
		else if (colorName == "Neon Carrot") cA = newArray(255,153,51);			/* #FF9933 */
		else if (colorName == "Sunglow") cA = newArray(255,204,51); 			/* #FFCC33 */
		else if (colorName == "Laser Lemon") cA = newArray(255,255,102); 		/* #FFFF66 "Unmellow Yellow" */
		else if (colorName == "Electric Lime") cA = newArray(204,255,0); 		/* #CCFF00 */
		else if (colorName == "Screamin' Green") cA = newArray(102,255,102); 	/* #66FF66 */
		else if (colorName == "Magic Mint") cA = newArray(170,240,209); 		/* #AAF0D1 */
		else if (colorName == "Blizzard Blue") cA = newArray(80,191,230); 		/* #50BFE6 Malibu */
		else if (colorName == "Dodger Blue") cA = newArray(9,159,255);			/* #099FFF Dodger Neon Blue */
		else if (colorName == "Shocking Pink") cA = newArray(255,110,255);		/* #FF6EFF Ultra Pink */
		else if (colorName == "Razzle Dazzle Rose") cA = newArray(238,52,210); 	/* #EE34D2 */
		else if (colorName == "Hot Magenta") cA = newArray(255,0,204);			/* #FF00CC AKA Purple Pizzazz */
		else restoreExit("No color match to " + colorName);
		return cA;
	}
	function setColorFromColorName(colorName) {
		colorArray = getColorArrayFromColorName(colorName);
		setColor(colorArray[0], colorArray[1], colorArray[2]);
	}