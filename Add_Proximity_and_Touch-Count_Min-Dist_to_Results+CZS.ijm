/*	ImageJ Macro to count the number of unique objects touching the each object
	Uniqueness is guaranteed by labeling each roi with a different grayscale that matches the roi number.
	Each ROI defined by an original object is expanded in pixel increments and the number of enclosed gray shades defines the number of objects now within that expansion
	Uses histogram macro functions so that no additional particle analysis is required.
	Peter J. Lee (NHMFL).
	v161108 adds a column for the minimum distance between each object and its closest neighbor.
	This version also has the CS SmartSEM function.
	v161109 adds check for edge objects.
	v170131 this version defaults to no correction for prior Watershed correction but provides option to enable it.
	v170824 changed to 16-bit label.
	v170909 Added garbage clean up as suggested by Luc LaLonde at LBNL.
	v170914 Minimum separation now set to zero for 1st iteration touches if Watershed option is selected.
	v180831 Corrected missing pixel statement in enlargement.	
*/
	requires("1.47r"); /* not sure of the actual latest working version byt 1.45 definitely doesn't work */
	saveSettings(); /* To restore settings at the end */
	/*   ('.')  ('.')   Black objects on white background settings   ('.')   ('.')   */	
	/* Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* Set the background to white */
	run("Colors...", "foreground=black background=white selection=yellow"); /* Set the preferred colors for these macros */
	setOption("BlackBackground", false);
	run("Appearance...", " "); /* do not use Inverting LUT - this does not help if the image already has one */
	/*	The above should be the defaults but this makes sure (black particles on a white background)
		http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	t = getTitle();
	binaryCheck(t);
	if (removeEdgeObjects() && roiManager("count")!=0) roiManager("reset"); /* macro does not make much sense if there are edge objects but perhaps they are not included in ROI list (you can cancel out of this). if the object removal routine is run it will also reset the ROI Manager list if it already contains entries */
	checkForRoiManager();
	
	run("Options...", "count=1 do=Nothing"); /* The binary count setting is set to "1" for consistent outlines */
	
	imageWidth = getWidth();
	imageHeight = getHeight();
	imageDims = (imageWidth + imageHeight);
	checkForUnits();
	iterationLimit = floor(minOf(255, (maxOf(imageWidth, imageHeight))/2));
	columnSuggest = minOf(10, iterationLimit);
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2; /* ---> add here the side size of 1 pixel in the new calibrated units (e.g. lcf=5, if 1 pixels is 5mm) <--- */
	/* create the dialog prompt */
	Dialog.create("Choose Iterations and Watershed Correction");
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
	print("-----\n\n");
	print("Proximity Count macro");
	print("Macro path: " + getInfo("macro.filepath"));
	print("Image used for count: " + t);
	print("Original magnification scale factor used = " + lcf + " with units: " + unit);
	print("Note that separations measured this way are only approximate for large separations.");
	maxExpansions = minOf(maxExpansionsD, iterationLimit); /* Enforce sensible iteration limit */	
	print("Maximum expansions requested = " + maxExpansionsD + " limited to " + maxExpansions + " or limited by " + expansionsListed + " columns requested in the Results table.");
	if (wCorr) print("Initial single pixel separation treated as touching i.e. Watershed separated.");
	createLabeledImage();		/* now create labeling image using rois */
	
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
		/* expand roi to include touching objects */
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
	print("Run time = " + (getTime()-start)/1000 + "s");
	print("-----\n\n");
	restoreSettings();
	setBatchMode("exit & display"); /* exit batch mode */
	run("Collect Garbage"); 
	showStatus("Macro Finished: " + roiManager("count") + " objects analyzed in " + (getTime()-start)/1000 + "s.");
	beep(); wait(300); beep(); wait(300); beep();
	/*
		( 8(|)	( 8(|)	ASC Functions	@@@@@:-)	@@@@@:-)
	*/
	function binaryCheck(windowTitle) { /* For black objects on a white background */
		selectWindow(windowTitle);
		if (is("binary")==0) run("8-bit");
		/* Quick-n-dirty threshold if not previously thresholded */
		getThreshold(t1,t2); 
		if (t1==-1)  {
			run("8-bit");
			setThreshold(0, 128);
			setOption("BlackBackground", true);
			run("Convert to Mask");
			run("Invert");
			}
		/* Make sure black objects on white background for consistency */
		if (((getPixel(0, 0))==0 || (getPixel(0, 1))==0 || (getPixel(1, 0))==0 || (getPixel(1, 1))==0))
			run("Invert"); 
		/*	Sometimes the outline procedure will leave a pixel border around the outside - this next step checks for this.
			i.e. the corner 4 pixels should now be all black, if not, we have a "border issue". */
		if (((getPixel(0, 0))+(getPixel(0, 1))+(getPixel(1, 0))+(getPixel(1, 1))) != 4*(getPixel(0, 0)) ) 
				restoreExit("Border Issue"); 	
	}
	function checkForPlugin(pluginName) {
		/* v161102 changed to true-false */
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
					subFolderCount = subFolderCount +1;
				}
			}
			subFolderList = Array.slice(subFolderList, 0, subFolderCount);
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
		/* v161109 adds the return of the updated ROI count and also adds dialog if there are already entries just in case . . */
		nROIs = roiManager("count");
		nRES = nResults; /* not really needed except to provide useful information below */
		if (nROIs==0) runAnalyze = true;
		else runAnalyze = getBoolean("There are already " + nROIs + " in the ROI manager; do you want to clear the ROI manager and reanalyze?");
		if (runAnalyze) {
			roiManager("reset");
			Dialog.create("Analysis check");
			Dialog.addCheckbox("Run Analyze-particles to generate new roiManager values?", true);
			Dialog.addMessage("This macro requires that all objects have been loaded into the ROI manager.\n \nThere are still " + nRES +" results.\nThe ROI list has, however, been cleared (to avoid accidental reuse).");
			Dialog.show();
			analyzeNow = Dialog.getCheckbox();
			if (analyzeNow) {
				setOption("BlackBackground", false);
				if (nResults==0)
					run("Analyze Particles...", "display add");
				else run("Analyze Particles..."); /* Let user select settings */
				if (nResults!=roiManager("count"))
					restoreExit("Results and ROI Manager counts do not match!");
			}
			else restoreExit();
		}
		return roiManager("count"); /* Returns the new count of entries */
	}
	function checkForUnits() {
		/* v161108 (adds inches to possible reasons for checking calibration)
			This version requires these functions:
			checkForPlugin, setScaleFromCZSemHeader
		*/
		getPixelSize(unit, pixelWidth, pixelHeight);
		if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches"){
			Dialog.create("No Units");
			tiff = matches(getInfo("image.filename"),".*[tT][iI][fF].*");
			if (matches(getInfo("image.filename"),".*[tT][iI][fF].*") && (checkForPlugin("tiff_tags.jar"))) {
				Dialog.addCheckbox("Unit asymmetry, pixel units or dpi remnants; do you want to try and import scale for CZ SEM tag?", true);
				Dialog.show();
				setCZScale = Dialog.getCheckbox;
				if (setCZScale) { /* Based on the macro here: https://rsb.info.nih.gov/ij/macros/SetScaleFromTiffTag.txt */
					setScaleFromCZSemHeader();
					getPixelSize(unit, pixelWidth, pixelHeight);
					if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="") setCZScale=false;
				}
				if(!setCZScale) {
					Dialog.create("Still no standard units");
					Dialog.addCheckbox("pixelWidth = " + pixelWidth + ": Do you want to define units for this image?", true);
					Dialog.show();
					setScale = Dialog.getCheckbox;
					if (setScale)
					run("Set Scale...");
				}
			}
			else if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches"){
				Dialog.create("Still no standard units");
				Dialog.addCheckbox("Unit asymmetry, pixel units or dpi remnants; do you want to define units for this image?", true);
				Dialog.show();
				setScale = Dialog.getCheckbox;
				if (setScale)
					run("Set Scale...");
			}
		}
	}
	function closeImageByTitle(windowTitle) {  /* Cannot be used with tables */
		if (isOpen(windowTitle)) {
		selectWindow(windowTitle);
		close();
		}
	}
	function createLabeledImage() {
		/* v170818 */
		newImage("Labeled", "16-bit black", imageWidth, imageHeight, 1);
		if (roiManager("count")>=65536) restoreExit("The labeling function is limited to 65536 objects");
		for (i=0 ; i<roiManager("count"); i++) {
			roiManager("select", i);
			labelValue = i+1;
			run("Add...", "value=[labelValue]");
		}
		run("Select None");
	}
	function removeEdgeObjects(){
	/*	Remove black edge objects without using Analyze Particles
	Peter J. Lee  National High Magnetic Field Laboratory
	requires the versatile wand tool: https://imagej.nih.gov/ij/plugins/versatile-wand-tool/index.html by Michael Schmid
	as built in wand does not select edge objects
	This version v161109
	*/
		if (!checkForPlugin("Versatile_Wand_Tool.java") && !checkForPlugin("versatile_wand_tool.jar")) exit("Versatile Wand Tool required for this macro");
		run("Select None");
		imageWidth = getWidth(); imageHeight = getHeight();
		makeRectangle(1, 1, imageWidth-2, imageHeight-2);
		run("Make Inverse");
		getStatistics(null, null, borderMin, borderMax);
		run("Select None");
		removeObjects = false;
		if(borderMin!=borderMax) {
			removeObjects = getBoolean("There appear to be edge objects; do you want to remove them?");
			if (removeObjects) {
				if (is("Inverting LUT")) { /* At least this should resolve any visual confusion */
					run("Invert LUT");
					run("Invert");
				}
				imageHeight2 = getHeight()+4; imageWidth2 = getWidth()+4;
				originalBGCol = getValue("color.background");
				if (originalBGCol!=0) setBackgroundColor(0);
				run("Canvas Size...", "width=[imageWidth2] height=[imageHeight2] position=Center");
				call("Versatile_Wand_Tool.doWand", 1, 1, 0, "8-connected");
				run("Invert");
				run("Make Inverse");
				run("Crop");
				run("Select None");
				if (originalBGCol!=0) setBackgroundColor(originalBGCol); /* Return background to original color */
			}
		}
		showStatus("Remove_Edge_Objects function complete");
		return removeObjects;
	}
	function restoreExit(message){ /* Make a clean exit from a macro, restoring previous settings */
		/* 9/9/2017 added Garbage clean up suggested by Luc LaLonde - LBNL */
		restoreSettings(); /* Restore previous settings before exiting */
		setBatchMode("exit & display"); /* Probably not necessary if exiting gracefully but otherwise harmless */
		run("Collect Garbage"); 
		exit(message);
	}
	function setScaleFromCZSemHeader() {
	/*	This very simple function sets the scale for SEM images taken with the Carl Zeiss SmartSEM program. It requires the tiff_tags plugin written by Joachim Wesner. It can be downloaded from http://rsbweb.nih.gov/ij/plugins/tiff-tags.html
	 There is an example image available at http://rsbweb.nih.gov/ij/images/SmartSEMSample.tif
	 This is the number of the VERY long tag that stores all the SEM information See original Nabble post by Pablo Manuel Jais: http://imagej.1557.x6.nabble.com/Importing-SEM-images-with-scale-td3689900.html imageJ version: https://rsb.info.nih.gov/ij/macros/SetScaleFromTiffTag.txt
	v161103 with minor tweaks by Peter J. Lee National High Magnetic Field Laboratory
	 v161108 adds Boolean unit option
	*/
	/* Gets the path+name of the active image */
	path = getDirectory("image");
	if (path=="") exit ("path not available");
	name = getInfo("image.filename");
	if (name=="") exit ("name not available");
	if (!matches(getInfo("image.filename"),".*[tT][iI][fF].*")) exit("Not a TIFF file \(original Zeiss TIFF file required\)");
	if (!checkForPlugin("tiff_tags.jar")) exit("Not a TIFF file \(original Zeiss TIFF file required\)");
	path = path + name;
	/* 
	Gets the tag, and parses it to get the pixel size information */
	tag = call("TIFF_Tags.getTag", path, 34118);
	i0 = indexOf(tag, "Image Pixel Size = ");
	if (i0!=-1) {
		i1 = indexOf(tag, "=", i0);
		i2 = indexOf(tag, "AP", i1);
		if (i1==-1 || i2==-1 || i2 <= i1+4)
		   exit ("Parsing error! Maybe the file structure changed?");
		text = substring(tag,i1+2,i2-2);
		/* 
		Splits the pixel size in number+unit and sets the scale of the active image */
		splits=split(text);
		setVoxelSize(splits[0], splits[0], 1, splits[1]);
	}
	else noTagCont = getBoolean("No CZSem tag found; do you want to continue?");
	if (noTagCont) run("Set Scale...");
	}