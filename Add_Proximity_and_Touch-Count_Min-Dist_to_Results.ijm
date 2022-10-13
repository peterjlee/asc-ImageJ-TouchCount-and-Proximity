/*	ImageJ Macro to count the number of unique objects touching the each object.
	Uniqueness is guaranteed by labeling each roi with a different grayscale that matches the roi number.
	Each ROI defined by an original object is expanded in pixel increments and the number of enclosed gray shades defines the number of objects now within that expansion
	Uses histogram macro functions so that no additional particle analysis is required.
	Peter J. Lee (NHMFL).
	v161108 adds a column for the minimum distance between each object and its closest neighbor.
	v161109 adds check for edge objects.
	v170131 this version defaults to no correction for prior Watershed correction but provides option to enable it.
	v170824 changed to 16-bit label.
	v170909 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	v170914 Minimum separation now set to zero for 1st iteration touches if Watershed option is selected.
	v180831 Corrected missing pixel statement in enlargement.
	v190725 Updates all ASC functions. v191122 Minor tweaks
	v200102-v220701 Updated functions f1 updated color functions and replaced binary[-]Check function with toWhiteBGBinary f2: updated functions.
*/
	requires("1.47r"); /* not sure of the actual latest working version but 1.45 definitely doesn't work */
	macroL = "Add_Proximity_and_Touch-Count_Min-Dist_to_Results_v220823.ijm";
	saveSettings(); /* To restore settings at the end */
	/*   ('.')  ('.')   Black objects on white background settings   ('.')   ('.')   */	
	/* Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	run("Appearance...", " "); if(is("Inverting LUT")) run("Invert LUT"); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background) http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	t = getTitle();
	toWhiteBGBinary(t);
	if (removeEdgeObjects() && roiManager("count")!=0) roiManager("reset"); /* macro does not make much sense if there are edge objects but perhaps they are not included in ROI list (you can cancel out of this). if the object removal routine is run it will also reset the ROI Manager list if it already contains entries */
	nROIs = checkForRoiManager();
	run("Options...", "count=1 do=Nothing"); /* The binary count setting is set to "1" for consistent outlines */
	imageWidth = getWidth();
	imageHeight = getHeight();
	checkForUnits();
	iterationLimit = floor(minOf(255, (maxOf(imageWidth, imageHeight))/2));
	columnSuggest = minOf(10, iterationLimit);
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2; /* ---> add here the side size of 1 pixel in the new calibrated units (e.g. lcf=5, if 1 pixels is 5mm) <--- */
	/* create the dialog prompt */
	Dialog.create("Choose Iterations and Watershed Correction \(" + macroL + "\)");
		Dialog.addNumber("No. of expansion touch count columns in Results Table:", columnSuggest, 0, 3, " Each iteration = " + pixelWidth + " " + unit);
		Dialog.addNumber("Maximum number of pixel expansions (" + iterationLimit + " max):", iterationLimit, 0, 3, " " + iterationLimit + " expansions = " + iterationLimit * pixelWidth + " " + unit);
		Dialog.setInsets(-2, 70, 10);
		Dialog.addMessage("Important: There needs to be a background border that is greater than this\nexpansion limit for the ImageJ-enlarge command used here to work properly.");
		Dialog.addCheckbox("Treat single pixel separation as touching, i.e. for Watershed separated objects.", false);
		Dialog.setInsets(-2, 30, 0);
		Dialog.addMessage("If checked the 1st pixel separation will be assumed to be zero\nassuming they were originally joined before separation.");
	Dialog.show;	
		expansionsListed = Dialog.getNumber; /* optional number of expansions displayed in the table (you do not have to list any if the min dist is all you want */
		maxExpansionsD = Dialog.getNumber; /* put a limit of how many expansions before quitting NOTE: the maximum is 255 */
		wCorr = Dialog.getCheckbox;
	IJ.log("-----\n\n");
	IJ.log("Proximity Count macro \(" + macroL + "\)");
	IJ.log("Image used for count: " + t);
	IJ.log("Original magnification scale factor used = " + lcf + " with units: " + unit);
	IJ.log("Note that separations measured this way are only approximate for large separations.");
	maxExpansions = minOf(maxExpansionsD, iterationLimit); /* Enforce sensible iteration limit */	
	IJ.log("Maximum expansions requested = " + maxExpansionsD + " limited to " + maxExpansions + " or limited by " + expansionsListed + " columns requested in the Results table.");
	if (wCorr) IJ.log("Initial single pixel separation treated as touching i.e. Watershed separated.");
	createLabeledImage();		/* now create labeling image using ROIs */
	roiOriginalCount = roiManager("count");
	minDistArray = newArray(roiOriginalCount);
	start = getTime(); /* start timer after last requester for debugging */
	setBatchMode(true);
	showStatus("Looping through all " + roiOriginalCount + " objects for touching and proximity neighbors . . .");
	for (i=0 ; i<roiOriginalCount; i++) {
		showProgress(-i, roiManager("count"));
		selectWindow("Labeled");
		roiManager("select", i);
		Roi.getBounds(Rx, Ry, Rwidth, Rheight);
		minDistArray[i] = -1; /* sets array value so that 1st true entry is flagged */
		if (wCorr) jStart = 2;
		else jStart = 1;
		/* expand ROI to include touching objects */
		for (j=jStart ; j<maxExpansions; j++) { /*  if selected above first expansion is just 1 pixel boundary (assuming watershed separation) so start at 2 */
			selectWindow("Labeled");
			roiManager("select", i);
			run("Enlarge...", "enlarge=[j] pixel");
			run("Copy"); /* copy and paste is significantly faster than duplicate - does not require clearing outside */
			newImage("enlarged","16-bit black",Rwidth+2*j+2,Rheight+2*j+2,1);
			run("Paste");
			getRawStatistics(count, mean, min, max, std);
			nBins = 1 + max - min;
			getHistogram(null, counts, nBins, min, max);
			counts = Array.sort(counts);
			counts = Array.reverse(counts);
			GrayCount = 0;
			for (k=0; k<nBins; k++) { /* count the number of individual gray levels from histogram levels */
				if (counts[k]!=0) GrayCount = GrayCount+1;
				else k = nBins;  /* end gray counting loop on first empty histogram value - no more gray columns */
			}
			ProxCount = GrayCount - 2; /* Correct for background and original object */
			Separation = lcf*(j-1); /* only the selected object is expanded so this does not have to be corrected for adjacent expansion */
			if (ProxCount>0 && minDistArray[i]==-1) minDistArray[i] = Separation; /* first non-zero proximity count defines min dist */
			if (lcf>1 && lcf<10) Separation = d2s(Separation, 1) ;
			if (lcf>=10) Separation = d2s(Separation, 0);
			if (wCorr && j==2) {
				setResult("Touch.N.", i, ProxCount); /* For Watershed separated */
				if (ProxCount>0) minDistArray[i] = 0; /* For Watershed separated, 1 pixel separation is assumed to be zero. */
			}
			if (!wCorr && j==1) setResult("Touch.N.", i, ProxCount);
			else if (lcf==1) {
				if(j<expansionsListed+3) setResult("TN+" + Separation + "\(px\)", i, ProxCount);
				if(minDistArray[i]>-1) {
					setResult("MinSep\(px\)", i, minDistArray[i]);
					if (j>expansionsListed+2) j = 255; /* No point continuing to expand if all the requested data has been generated */
				}
				else if (j>maxExpansions-2) setResult("MinSep\(px\)", i, "\>" + Separation + "\(px\)");
			}
			else if (lcf!=1) {
				if(j<expansionsListed+3) setResult("TN+"+Separation+ "\(" + unit + "\)", i, ProxCount);   
				if(minDistArray[i]>-1) {
					setResult("MinSep\(" + unit + "\)", i, minDistArray[i]);
					if (j>expansionsListed+2) j = 255; /* No point continuing to expand if all the requested data has been generated */
				}
				else if (j>maxExpansions-2) setResult("MinSep\(" + unit + "\)", i, "\>" + Separation);
			}
			close("enlarged");
			if (minDistArray[i]>-1 && j>maxExpansions) j=255;
		}
	}
	closeImageByTitle("Labeled");
	IJ.log("Run time = " + (getTime()-start)/1000 + "s");
	IJ.log("-----\n\n");
	restoreSettings();
	setBatchMode("exit & display"); /* exit batch mode */
	run("Collect Garbage"); 
	showStatus("!Proximity Macro Finished: " + roiManager("count") + " objects analyzed in " + (getTime()-start)/1000 + "s.");
	beep(); wait(300); beep(); wait(300); beep();
	/*
		( 8(|)	( 8(|)	ASC Functions	@@@@@:-)	@@@@@:-)
	*/
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
			v180831 some cleanup
			v210429 Expandable array version
			v220510 Looks for both class and jar if no extension is given
			v220818 Mystery issue fixed, no longer requires restoreExit	*/
		pluginCheck = false;
		if (getDirectory("plugins") == "") print("Failure to find any plugins!");
		else {
			pluginDir = getDirectory("plugins");
			if (lastIndexOf(pluginName,".")==pluginName.length-1) pluginName = substring(pluginName,0,pluginName.length-1);
			pExts = newArray(".jar",".class");
			knownExt = false;
			for (j=0; j<lengthOf(pExts); j++) if(endsWith(pluginName,pExts[j])) knownExt = true;
			pluginNameO = pluginName;
			for (j=0; j<lengthOf(pExts) && !pluginCheck; j++){
				if (!knownExt) pluginName = pluginName + pExts[j];
				if (File.exists(pluginDir + pluginName)) {
					pluginCheck = true;
					showStatus(pluginName + "found in: "  + pluginDir);
				}
				else {
					pluginList = getFileList(pluginDir);
					subFolderList = newArray;
					for (i=0,subFolderCount=0; i<lengthOf(pluginList); i++) {
						if (endsWith(pluginList[i], "/")) {
							subFolderList[subFolderCount] = pluginList[i];
							subFolderCount++;
						}
					}
					for (i=0; i<lengthOf(subFolderList); i++) {
						if (File.exists(pluginDir + subFolderList[i] +  "\\" + pluginName)) {
							pluginCheck = true;
							showStatus(pluginName + " found in: " + pluginDir + subFolderList[i]);
							i = lengthOf(subFolderList);
						}
					}
				}
			}
		}
		return pluginCheck;
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
			v220823: Extended corner pixel test.
			*/
		functionL = "checkForRoiManager_v220816";
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
				Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are   " + nRes +"   results.\nThere are   " + nROIs +"   ROIs.\nDo you want to:");
				mismatchOptions = newArray();
				if(nROIs==0) mismatchOptions = Array.concat(mismatchOptions,"Import a saved ROI list");
				else mismatchOptions = Array.concat(mismatchOptions,"Replace the current ROI list with a saved ROI list");
				if(nRes==0) mismatchOptions = Array.concat(mismatchOptions,"Import a Results Table \(csv\) file");
				else mismatchOptions = Array.concat(mismatchOptions,"Clear Results Table and import saved csv");
				mismatchOptions = Array.concat(mismatchOptions,"Clear ROI list and Results Table and reanalyze \(overrides above selections\)");
				if (!is("binary")) Dialog.addMessage("The active image is not binary, so it may require thresholding before analysis");
				mismatchOptions = Array.concat(mismatchOptions,"Get me out of here, I am having second thoughts . . .");
				Dialog.addRadioButtonGroup("ROI mismatch; what would you like to do:_____", mismatchOptions, lengthOf(mismatchOptions), 1, mismatchOptions[0]);
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
							setOption("BlackBackground", false);
							run("Make Binary");
						}
					}
				}
				if (is("Inverting LUT"))  run("Invert LUT");
				/* Make sure black objects on white background for consistency */
				if (bitDepth()!=24){
					yMax = Image.height-1;	xMax = Image.width-1;
					cornerPixels = newArray(getPixel(0,0),getPixel(1,1),getPixel(0,yMax),getPixel(xMax,0),getPixel(xMax,yMax),getPixel(xMax-1,yMax-1));
					Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
					if (cornerMax!=cornerMin) restoreExit("cornerMax="+cornerMax+ " but cornerMin=" +cornerMin+ " and cornerMean = "+cornerMean+" problem with image border");
					/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
						i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
					if (cornerMean<1 && cornerMean!=-1) {
						inversion = getBoolean("The corner mean has an intensity of " + cornerMean + ", do you want the intensities inverted?", "Yes Please", "No Thanks");
						if (inversion) run("Invert");
					}
				}
				if (isOpen("ROI Manager"))	roiManager("reset");
				setOption("BlackBackground", false);
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
		 v200925 looks for pixels unit too; v210428 just adds function label
		NOTE: REQUIRES ASC restoreExit function which requires previous run of saveSettings		 */
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
		   v200925 uses "while" instead of "if" so that it can also remove duplicates
		*/
		oIID = getImageID();
        while (isOpen(windowTitle)) {
			selectWindow(windowTitle);
			close();
		}
		if (isOpen(oIID)) selectImage(oIID);
	}
	function createLabeledImage() {
		/* v200306 requires restoreExit function
		NOTE: REQUIRES ASC restoreExit function which requires previous run of saveSettings		*/
		labels = roiManager("count");
		if (labels==0) restoreExit("Sorry, this macro labels using ROI Manager objects, try the Landini plugin instead.");
		if (labels>=65536) restorExit("The labeling function is limited to 65536 objects");
		if (labels<=253)	newImage("Labeled", "8-bit black", imageWidth, imageHeight, 1);
		else newImage("Labeled", "16-bit black", imageWidth, imageHeight, 1);
		for (i=0 ; i<labels; i++) {
			roiManager("select", i);
			labelValue = i+1;
			run("Add...", "value=[labelValue]");
			if (nResults==labels) setResult("Label\(Int\)", i, labelValue);
		}
		run("Select None");
	}
	function removeEdgeObjects(){
	/*	Remove black edge objects without using Analyze Particles
	Peter J. Lee  National High Magnetic Field Laboratory
	Requires:
		The versatile wand tool: https://imagej.nih.gov/ij/plugins/versatile-wand-tool/index.html by Michael Schmid as built in wand does not select edge objects
		checkForEdgeObjects function
	Optional: morphology_collection.jar
	1st version v190604
	v190605 This version uses Gabriel Landini's morphology plugin if available.
	v190725 Checks for edges first and then returns "true" if edge objects removed.
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
		/* 9/9/2017 added Garbage clean up suggested by Luc LaLonde - LBNL */
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		run("Collect Garbage"); 
		exit(message);
	}
	function toWhiteBGBinary(windowTitle) { /* For black objects on a white background */
		/* Replaces binary[-]Check function
		v220707
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
		if (is("Inverting LUT")) run("Invert LUT");
		/* Make sure black objects on white background for consistency */
		yMax = Image.height-1;	xMax = Image.width-1;
		cornerPixels = newArray(getPixel(0,0),getPixel(1,1),getPixel(0,yMax),getPixel(xMax,0),getPixel(xMax,yMax),getPixel(xMax-1,yMax-1));
		Array.getStatistics(cornerPixels, cornerMin, cornerMax, cornerMean, cornerStdDev);
		if (cornerMax!=cornerMin) IJ.log("Warning: There may be a problem with the image border, there are different pixel intensities at the corners");
		/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
		if (cornerMean<1) run("Invert");
	}