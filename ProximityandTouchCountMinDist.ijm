/*	ImageJ Macro to count the number of unique objects touching the each object
	Uniqueness is guaranteed by labeling each roi with a different grayscale that matches the roi number
	Each ROI defined by an original object is epanded in pixel increments and the number of enclosed gray shades defines the number of objects now within that expansion
	Uses histogram macro functions so that no additional particle analysis is required.
	6/9/2016 Peter J. Lee (NHMFL)
	This version: v161108 adds a column for the minimum distance between each object and its closest neighbor
	v161109 adds check for edge objects
*/
	requires("1.47r"); /* not sure of the actual latest working version byt 1.45 definitely doesn't work */
	saveSettings(); /* To restore settings at the end */
	/*   ('.')  ('.')   Black objects on white background settings   ('.')   ('.')   */	
	/* Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* set white background */
	run("Colors...", "foreground=black background=white selection=yellow"); /* set colors */
	setOption("BlackBackground", false);
	run("Appearance...", " "); /* do not use Inverting LUT - this does not help if the image already has one */
	/*	The above should be the defaults but this makes sure (black particles on a white background)
		http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	t = getTitle();
	binaryCheck(t);
	if (removeEdgeObjects() && roiManager("count")!=0) roiManager("reset"); /* macro does not make much sense if there are edge objects but perhaps they are not included in ROI list (you can cancel out of this). if the object removal routine is run it will also reset the ROI Manager list if it already contains entries */
	checkForRoiManager();
	start = getTime(); /* start timer after last requester for debugging */
	setBatchMode(true);
		
	run("Options...", "count=1 do=Nothing"); /* The binary count setting is set to "1" for consistent outlines */

	imageWidth = getWidth();
	imageHeight = getHeight();
	imageDims = (imageWidth + imageHeight);
	checkForUnits();
	getPixelSize(unit, pixelWidth, pixelHeight);
	lcf=(pixelWidth+pixelHeight)/2; /* ---> add here the side size of 1 pixel in the new calibrated units (e.g. lcf=5, if 1 pixels is 5mm) <--- */
	/* create the dialog prompt */
	Dialog.create("Choose Iterations");
		Dialog.addNumber("No. of expansion touch count columns to be listed in table:", 10, 0, 3, " Each iteration = " + pixelWidth + " " + unit);
		Dialog.addNumber("Limit total number of expansions (255 max)?", 255, 0, 3, " 255 expansions = " + 255 * pixelWidth + " " + unit);
	Dialog.show;	
		expansionsListed = Dialog.getNumber; /* optional number of expansions displayed in the table (you do not have to list any if the min dist is all you want */
		maxExpansions = Dialog.getNumber; /* put a limit of how many expansions before quitting NOTE: the maximum is 255 */
	maxExpansions = minOf(maxExpansions, 255); /* There is a limit of 255 */	
	createLabeledImage();		/* now create labeling image using rois */
	roiOriginalCount = roiManager("count");
	minDistArray = newArray(roiOriginalCount);
	showStatus("Looping through all " + roiOriginalCount + " objects for touching and proximity neighbors . . .");
	for (i=0 ; i<roiOriginalCount; i++) {
		showProgress(-i, roiManager("count"));
		selectWindow("Labeled");
		roiManager("select", i);
		Roi.getBounds(Rx, Ry, Rwidth, Rheight);
		minDistArray[i] = -1; /* sets array value so that 1st true entry is flagged */
		/* expand roi to include touching objects */
		for (j=2 ; j<maxExpansions; j++) { /* first expansion is just 1 pixel boundary (assuming watershed separation) so start at 2 */
			selectWindow("Labeled");
			roiManager("select", i);
			run("Enlarge...", "enlarge=[j]");
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
			Separation = lcf*(j-2); /* only the selected object is expanded so this does not have to be corrected for adjacent expansion */
			if (ProxCount>0 && minDistArray[i]==-1) minDistArray[i] = Separation; /* first non-zero proximity count defines min dist */
			if (lcf>1 && lcf<10) Separation = d2s(Separation, 1) ;
			if (lcf>=10) Separation = d2s(Separation, 0);
			if (j==2) setResult("Touch.N.", i, ProxCount);
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
	print("-----\n\n");
	print("Proximity Count macro");
	print("Macro path: " + getInfo("macro.filepath"));
	print("Image used for count: " + t);
	print("Original magnification scale factor used = " + lcf + " with units: " + unit);
	print("Note that separations measured this way are only approximate for large separations.");
	print("Run time = " + (getTime()-start)/1000 + "s");
	print("-----\n\n");
	restoreSettings();
	setBatchMode("exit & display"); /* exit batch mode */
	showStatus("Macro Finished: " + roiManager("count") + " objects analyzed in " + (getTime()-start)/1000 + "s.");
	beep(); wait(300); beep(); wait(300); beep();
	/*
		( 8(|)	( 8(|)	All ASC Functions	@@@@@:-)	@@@@@:-)
	*/
	function binaryCheck(windowTitle) { /* for black objects on white background */
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
			subFolderList = newArray(pluginList.length);
			for (i=0; i<pluginList.length; i++) {
				if (endsWith(pluginList[i], "/")) {
					subFolderList[subFolderCount] = pluginList[i];
					subFolderCount = subFolderCount +1;
				}
			}
			subFolderList = Array.slice(subFolderList, 0, subFolderCount);
			for (i=0; i<subFolderList.length; i++) {
				if (File.exists(pluginDir + subFolderList[i] +  "\\" + pluginName)) {
					pluginCheck = true;
					showStatus(pluginName + " found in: " + pluginDir + subFolderList[i]);
					i = subFolderList.length;
				}
			}
		}
		return pluginCheck;
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
			Dialog.addMessage("This macro requires that all objects have been loaded into the roi manager.\n \nThere are still " + nRES +" results.\nThe ROI list has, however, been cleared (to avoid accidental reuse).");
			Dialog.show();
			analyzeNow = Dialog.getCheckbox();
			if (analyzeNow) {
				setOption("BlackBackground", false);
				if (nResults==0)
					run("Analyze Particles...", "display add");
				else run("Analyze Particles..."); /* let user select settings */
				if (nResults!=roiManager("count"))
					restoreExit("Results and ROI Manager counts do not match!");
			}
			else restoreExit();
		}
		return roiManager("count"); /* returns the new count of entries */
	}
	function checkForUnits() {  /* 
		/* v161108 (adds inches to possible reasons for checking calibration)
		*/
		getPixelSize(unit, pixelWidth, pixelHeight);
		if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches"){
			Dialog.create("No Units");
			Dialog.addCheckbox("Unit asymmetry, pixel units or dpi remnants; do you want to define units for this image?", true);
			Dialog.show();
			setScale = Dialog.getCheckbox;
			if (setScale) run("Set Scale...");
		}
	}
	function closeImageByTitle(windowTitle) {  /* cannot be used with tables */
        if (isOpen(windowTitle)) {
		selectWindow(windowTitle);
        close();
		}
	}
	function createLabeledImage() {
		newImage("Labeled", "32-bit black", imageWidth, imageHeight, 1);
		for (i=0 ; i<roiManager("count"); i++) {
			roiManager("select", i);
			setColor(1+i);
			fill(); /* This only only works for 32-bit images so hopefully it is not a bug */
		}
	}
	function removeEdgeObjects(){
	/*	Remove black edge objects without using analyze particles
	Peter J. Lee  National High Magnetic Field Laboratory
	Requies the versatile wand tool: https://imagej.nih.gov/ij/plugins/versatile-wand-tool/index.html by Michael Schmid
	as built in wand does not select edge objects
	This version v161109
	*/
		if (!checkForPlugin("Versatile_Wand_Tool.java") && !checkForPlugin("versatile_wand_tool.jar")) exit("Versatile want tool required");
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
				if (is("Inverting LUT")) { /* at least this should resolve any confusion */
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
				if (originalBGCol!=0) setBackgroundColor(originalBGCol); /* return background to original color */
			}
		}
		showStatus("Remove_Edge_Objects function complete");
		return removeObjects;
	}
	function restoreExit(message){ /* clean up before aborting macro then exit */
		restoreSettings(); /* clean up before exiting */
		setBatchMode("exit & display"); /* not sure if this does anything useful if exiting gracefully but otherwise harmless */
		exit(message);
	}