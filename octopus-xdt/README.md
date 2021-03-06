# Test-Xdt

A tool for spot-checking XDT transforms as used by Octopus Deploy [configuration transforms](http://docs.octopusdeploy.com/display/OD/Configuration+files) prior to a deployment.

The main reason for developing this is the gap between what will "fail" a MsBuild/VS XML transform and what will fail an Octopus Tentacle transform (by default). 

Alternatively, you can set the [system variable](http://docs.octopusdeploy.com/display/OD/System+variables) `IgnoreConfigTransformationErrors` in your project.

This utilizes code and mimics behavior of Octopus Tentacles' [Calarmi](https://github.com/OctopusDeploy/Calamari/blob/master/source/Calamari/Integration/ConfigurationTransforms/ConfigurationTransformer.cs) which in turn l leverages [Microsoft.Web.Xdt](https://www.nuget.org/packages/Microsoft.Web.Xdt/)
