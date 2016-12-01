/*	ImageJ Macro to count the number of unique objects touching the each object
	Uniqueness is guaranteed by labeling each roi with a different grayscale that matches the roi number
	Each ROI defined by an original object is epanded in pixel increments and the number of enclosed gray shades defines the number of objects now within that expansion
	Uses histogram macro functions so that no additional particle analysis is required.
	6/9/2016 Peter J. Lee (NHMFL)
	This version: v161108 adds a column for the minimum distance between each object and its closest neighbor
	This version also has the CS SmartSEM function
*/
	saveSettings(); /* To restore settings at the end */
	/*   ('.')  ('.')   Black objects on white background settings   ('.')   ('.')   */	
	/* Set options for black objects on white background as this works better for publications */
	run("Options...", "iterations=1 white count=1"); /* set white background */
	run("Colors...", "foreground=black background=white selection=yellow"); /* set colors */
	setOption("BlackBackground", false);
	run("Appearance...", " "); /* do not use Inverting LUT */
	/*	The above should be the defaults but this makes sure (black particles on a white background)
		http://imagejdocu.tudor.lu/doku.php?id=faq:technical:how_do_i_set_up_imagej_to_deal_with_white_particles_on_a_black_background_by_default
	*/
	t = getTitle();
	binaryCheck(t);
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

	/* now create labeling image using rois */
	createLabeledImage();
	roiOriginalCount = roiManager("count");
	minDistArray = newArray(roiOriginalCount);
	showStatus("Looping through all " + roiOriginalCount + " objects for touching and proximity neighbors . . .");
	for (i=0 ; i<roiOriginalCount; i++) {
		showProgress(-i, roiManager("count"));
		selectWindow("Labeled");
		roiManager("select", i);
		Roi.getBounds(Rx, Ry, Rwidth, Rheight);
		minDistArray[i] = -1;
		/* expand roi to include touching objects */
		for (j=2 ; j<maxExpansions; j++) { /* first expansion is just 1 pixel boundary so start at 2 */
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
	}
	function checkForRoiManager() {
		nROIs = roiManager("count");
		nRES = nResults;
		if (nROIs==0)  {
			Dialog.create("No ROI");
			Dialog.addCheckbox("Run Analyze-particles to generate roiManager values?", true);
			Dialog.addMessage("This macro requires that all objects have been loaded into the roi manager.\n \nThere are   " + nRES +"   results.\nThere are   " + nROIs +"   ROIs.");
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
				if (setCZScale) { /* based in macro here: https://rsb.info.nih.gov/ij/macros/SetScaleFromTiffTag.txt */
					setScaleFromCZSemHeader();
					getPixelSize(unit, pixelWidth, pixelHeight);
					if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="") setCZScale=false;
				}
				if(!setCZScale) {
					Dialog.create("No Units Still");
					Dialog.addCheckbox("pixelWidth = " + pixelWidth + ": Do you want to define units for this image?", true);
					Dialog.show();
					setScale = Dialog.getCheckbox;
					if (setScale)
					run("Set Scale...");
				}
			}
			else if (pixelWidth!=pixelHeight || pixelWidth==1 || unit=="" || unit=="inches"){
				Dialog.create("No Sensible Units Still");
				Dialog.addCheckbox("Unit asymmetry, pixel units or dpi remnants; do you want to define units for this image?", true);
				Dialog.show();
				setScale = Dialog.getCheckbox;
				if (setScale)
					run("Set Scale...");
			}
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
	function restoreExit(message){ /* clean up before aborting macro then exit */
		restoreSettings(); /* clean up before exiting */
		setBatchMode("exit & display"); /* not sure if this does anything useful if exiting gracefully but otherwise harmless */
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
	if (!matches(getInfo("image.filename"),".*[tT][iI][fF].*")) exit("Not TIFF file");
	if (!checkForPlugin("tiff_tags.jar")) exit("Not TIFF file");
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