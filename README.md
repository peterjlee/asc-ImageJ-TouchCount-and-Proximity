# asc-ImageJ-TouchCount-and-Proximity
<p>These ImageJ macros (<a href="https://github.com/peterjlee/asc-ImageJ-TouchCount-and-Proximity" Title = "Applied Superconductivity Center Touch Count and Proximity Macro Directory" >link</a>):
<br />1: Count the number of objects that are touching each other<a href="https://fs.magnet.fsu.edu/~lee/asc/ImageJUtilities/ASC-Macros/LayerThickness/Minimum%20wall%20thickness%20macro_060816.pdf"></a>.
<br />2: Count the number of objects within successive spacing range increases of 1 pixel (up to 10 iterations).
<br />3: Report the minimum separation distance between objects.
<br />By default these macros assume that all objects have been previously separated by using a watershed tool (i.e.  &quot;touching&quot; objects will be separated by 1 pixel). Separation ranges are converted from pixels to the scaled unit if there is one (if just pixels are preferred just remove the scale prior to running the macro). The "CZS" version automatically pulls the scale information from CZS format headers. Note: there needs to be an empty background color border around all the outside objects that is at least as wide as the maximum measured separation.</p>

<p><img src="https://fs.magnet.fsu.edu/~lee/asc/ImageJUtilities/IA_Images/ProximityandTouchCount_Example_mplPlasma_anim573x190.gif" alt="Touch count of each object." width="572" height="190" /></p>

<p><sub><sup>
 <strong>Legal Notice:</strong> <br />
These macros have been developed to demonstrate the power of the ImageJ macro language and we assume no responsibility whatsoever for its use by other parties, and make no guarantees, expressed or implied, about its quality, reliability, or any other characteristic. On the other hand we hope you do have fun with them without causing harm.
<br />
The macros are continually being tweaked and new features and options are frequently added, meaning that not all of these are fully tested. Please contact me if you have any problems, questions or requests for new modifications.
 </sup></sub>
</p>
