<%!
  import os
  import glob
  import re
  import json
  from itertools import chain
  from routes import url_for

  prefix = url_for("/")
  path = os.getcwd()
  
%>
<%
  app_root = "config/plugins/visualizations/"+visualization_name+"/"
  
  ## list of string lines of input bio file
  data = ''.join(list(hda.datatype.dataprovider(
    hda, 
    'line', 
    strip_lines=True, 
    strip_newlines=True )))
  
  results = json.loads(data)
  
  # print(results.keys())
  ## [u'parameter_values', u'parameters', u'variables', u'results', u'states', u'parameter_bounds', u'type', u'thresholds']
  
  ## parssing of bio file format to python structures (later used in JS)
  vars =   [str(k) for k in results['variables']]
  params = [[str(k), results['parameter_bounds'][i][0], results['parameter_bounds'][i][1]] for i, k in enumerate(results['parameters'])]
  thrs =   dict({str(k) : results['thresholds'][i] for i, k in enumerate(results['variables'])}, 
                **{str(k) : results['parameter_bounds'][i] for i, k in enumerate(results['parameters'])})
  
  type = str(results['type'])
  states = {k['id']: k['bounds'] for k in results['states'] }
  params_val = results['parameter_values']
  results = {str(k['formula']): k['data'] for k in results['results'] }
  
%>
<html lan"en">
  
  <head>
    <title>Parameter Space</title>
  	<script src="https://d3js.org/d3.v4.js" charset="utf-8"></script>
  	<script type="text/javascript" charset="utf-8">
      // definition of functions used in bio files so there is no need to transorm them 
      function Hillm(x,t,n,b,a) {
        return a+(b-a)*(Math.pow(t,n)/(Math.pow(x,n)+Math.pow(t,n)));
      };
      hillm = Hillm;
      function Hillp(x,t,n,a,b) {
        return a+(b-a)*(Math.pow(x,n)/(Math.pow(x,n)+Math.pow(t,n)));
      };
      hillp = Hillp;
      function Approx(s,ramps) {
        if(s <= ramps[0][0]) return(ramps[0][1])
        if(s >= ramps[ramps.length-1][0]) return(ramps[ramps.length-1][1])
        for(var i = 1, len = ramps.length;  i < len; ++i) {
          a = ramps[i-1]
          b = ramps[i]
          if(s >= a[0] && s <= b[0]) return(a[1]+(s-a[0])/(b[0]-a[0])*(b[1]-a[1]))
        }
      }
      
      // creates one structure containing all data from result.json file for JS code
      window.bio = {'thrs': ${thrs}, 
                    'vars': ${vars}, 
                    'params': ${params}};
      window.result = {'type': "${type}", 
                       'states': ${states}, 
                       'params': ${params_val}, 
                       'map': ${results} };
      console.log(window.bio);
      console.log(window.result);
      
      Set.prototype.difference = function(setB) {
          var difference = new Set(this);
          for (var elem of setB) {
              difference.delete(elem);
          }
          return difference;
      };
      d3.selection.prototype.moveUp = function() {
          return this.each(function() {
              this.parentNode.appendChild(this);
          });
      };
      function parsing_to_string(x) {
        if(Object.values(x).length > 0) {
          var result = Number.parseFloat(Object.values(x)[0]).toFixed(2).toString();
          for(var i = 1; i < Object.values(x).length; ++i) {
            result += " "+Number.parseFloat(Object.values(x)[i]).toFixed(2).toString();
          }
          return result;
        } else return "";
      };
    </script>
  
    <!--meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1, maximum-scale=1"-->
    <style>
      body {
        background-color: white;
        margin: 0;
        font-family: sans-serif;
        font-size: 18px;
      }
      #cont {
        pointer-events: all;
      }
      #zoomObject {
      }
      .loop {
        vector-effect: non-scaling-stroke; 
      }
      .transition { 
        vector-effect: non-scaling-stroke; 
      }
      .states {
        vector-effect: non-scaling-stroke; 
      }
      .axis {
        font-size: 15px;
      }
      .widget_panel {
        position: absolute;
        left: 560px;
        height: 100%;
        width: 230px;
        
      }
      #resetZoomBtn {
        position: absolute;
        top: 10px;
      }
      #resetReachBtn {
        position: absolute;
        top: 40px;
      }
      #infoPanel {
        position: absolute;
        top: 70px;
        flex-grow: 1;
      }
      #x_axis_div {
        position: absolute;
        top: 160px;
        width: 90px;
      }
      #y_axis_div {
        position: absolute;
        top: 160px;
        width: 90px;
        left: 100px;
      }
      .slidecontainer {
        position: absolute;
        top: 200px;
      }
      #formula_div {
        position: absolute;
        top: 500px;
      }
    </style>
    
  </head>
  
  <body>
    <div class="widget_panel">
      <button id="resetZoomBtn">Unzoom</button>
      <button id="resetReachBtn">Deselect</button>
      <textarea id="infoPanel" rows="${len(params)+2}" cols="35" wrap="off" disabled></textarea>
      <!-- dynamicly adds sliders with labels for parameters and variables (if more than 2 vars are present) in mako style -->
      <div id="x_axis_div">
        X axis<br>
        <select name="xAxis" id="x_axis" style="width:90px" required>
          % for val in params:
            % if val[0] == params[0][0]:
              <option value="${val[0]}" selected>${val[0]}</option>
            % else:
              <option value="${val[0]}">${val[0]}</option>
            % endif
          % endfor
        </select>
      </div>
      <div id="y_axis_div">
        Y axis<br>
        <select name="yAxis" id="y_axis" style="width:90px" required>
          % for val in params:
            % if len(params) > 1 and val[0] == params[1][0]:
              <option value="${val[0]}" selected>${val[0]}</option>
            % else:
              <option value="${val[0]}">${val[0]}</option>
            % endif
          % endfor
        </select>
      </div>
      <div class="slidecontainer">
      <hr>
      % for val in params:
        <% 
        min_val  = float(val[1])
        max_val  = float(val[2])
        step_val = abs(max_val-min_val)*0.001
        %>
        % if val[0] == params[0][0] or val[0] == params[1][0]:
        <!--div id="slider_${val[0]}_wrapper" hidden-->
        <div id="slider_${val[0]}_wrapper">
        % else:
        <div id="slider_${val[0]}_wrapper">
        % endif
          par. ${val[0]}: <span id="text_${val[0]}"></span><br>
          <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_${val[0]}">
          <input type="checkbox" value="all" class="cb" id="checkbox_${val[0]}" checked>whole
        </div>
      % endfor
      <hr>
      % for val in vars:
        <% 
        min_val  = min(map(float,thrs[val]))
        max_val  = max(map(float,thrs[val]))
        step_val = abs(max_val-min_val)*0.01
        %>
        <div id="slider_${val}_wrapper">
          var. ${val}: <span id="text_${val}"></span><br>
          <input type="range" min=${min_val} max=${max_val} value=${min_val} step=${step_val} class="slider" id="slider_${val}">
          <input type="checkbox" value="all" class="cb" id="checkbox_${val}" checked>whole
        </div>
      % endfor
      </div>
      <div id="formula_div">
        <hr>
        Property<br>
        <select id="formula" style="width:190px" required>
          % for key, val in enumerate(results.keys()):
            % if key == 0:
              <option value="${val}" selected>${val}</option>
            % else:
              <option value="${val}">${val}</option>
            % endif
          % endfor
        </select>
        Param<br>
        <select id="param_id" style="width:190px" required>
            <option value="all" selected>all</option>
          % for key, val in enumerate(params_val):
            <option value="${key}">${key}</option>
          % endfor
        </select>
      </div>
    </div>
    
    <script type="text/javascript" charset="utf-8">
   
var xDim = document.getElementById("x_axis").value,
    yDim = document.getElementById("y_axis").value,
    xDim_id = window.bio.params.findIndex(x => x[0] == xDim),
    yDim_id = window.bio.params.findIndex(x => x[0] == yDim),
    thrs = window.bio.thrs,
    formula = document.getElementById("formula").value,
    sel_result_data = window.result.map[formula],
    sel_result_data_transposed = sel_result_data[0].map((col, i) => sel_result_data.map(row => row[i])),
    param_bounds = [];

// initial parametric bounds are not limited (projection through all parametric dimensions)
window.bio.params.forEach(x => param_bounds.push(null));

// iteratively adds event listener for variable sliders (according to index)
% for val in vars:
    (function(i) {
        d3.select("#text_"+i).html(d3.select("#slider_"+i).property("value"));
        
        d3.select("#slider_"+i).on("input", function() {
            d3.select("#text_"+i).html(this.value);

        });
    })('${val}');
% endfor

// iteratively adds event listener for parameter sliders (according to index)
% for key, val in enumerate(params):
    (function(i,d) {
        d3.select("#text_"+d[0]).html(d3.select("#slider_"+d[0]).property("value"));
        
        d3.select("#slider_"+d[0]).on("input", function() {
            d3.select("#text_"+d[0]).html(this.value);
            if(! d3.select("#checkbox_"+d[0]).property("checked")) {
                param_bounds[i] = Number(d3.select("#slider_"+d[0]).property("value"));
                compute_projection();
                draw();
            }
        });
        d3.select('#checkbox_'+d[0]).on("change", function() {
            if(! d3.select("#checkbox_"+d[0]).property("checked")) {
                param_bounds[i] = Number(d3.select("#slider_"+d[0]).property("value"));
            } else {
                param_bounds[i] = null;
            }
            compute_projection();
            draw();
        });
    })(${key},${val});
% endfor
  
// event listener for change of selectected dimension for X axis
d3.select("#x_axis").on("change", function() {
  var other = d3.select("#y_axis").property("value");
  if(this.value == other) {
    d3.select("#y_axis").property('value',xDim);
    yDim = xDim;
  } else {
//    d3.select("#slider_"+xDim+"_wrapper").attr("hidden",null);
  }
  xDim = this.value;
//  d3.select("#slider_"+this.value+"_wrapper").attr("hidden","hidden");
  xDim_id = window.bio.params.findIndex(x => x[0] == xDim);
  yDim_id = window.bio.params.findIndex(x => x[0] == yDim);

  resettedZoom();
  compute_projection();
  draw();
});

// event listener for change of selectected dimension for Y axis
d3.select("#y_axis").on("change", function() {
  var other = d3.select("#x_axis").property("value");
  if(this.value == other) {
    d3.select("#x_axis").property('value',yDim);
    xDim = yDim;
  } else {
//    d3.select("#slider_"+yDim+"_wrapper").attr("hidden",null);
  }
  yDim = this.value;
//  d3.select("#slider_"+this.value+"_wrapper").attr("hidden","hidden");
  xDim_id = window.bio.params.findIndex(x => x[0] == xDim);
  yDim_id = window.bio.params.findIndex(x => x[0] == yDim);

  resettedZoom();
  compute_projection();
  draw();
});

d3.select("#formula").on("change", function() {
  formula = d3.select("#formula").property("value");
    
  sel_result_data = window.result.map[formula];
  sel_result_data_transposed = sel_result_data.length > 0 ? sel_result_data[0].map((col, i) => sel_result_data.map(row => row[i])) : [];
  
  compute_projection();
  draw();
});

d3.select("#param_id").on("change", function() {
  
  compute_projection();
  draw();
});

d3.select('#resetReachBtn')
    .on("click", resettedClick);

d3.select('#resetZoomBtn')
    .on("click", resettedZoom);
    
//###################################################    

var width = 550,
    height = 550,
    margin = { top: 10, right: 10, bottom: 50, left: 50 },
    arrowlen = 7,
    color = "transparent",
    reachColor = "rgb(65, 105, 225)", // "royalblue"
    neutral_col = "black",
    positive_col = "darkgreen",
    negative_col = "red",
    normalStrokeWidth = 1,
    hoverStrokeWidth = 4,
    transWidth = 2,
    selfloopWidth = 4,
    projdata = [],
    zoomObject = d3.zoomIdentity;

// trans example = {
//   0:[0,1],
//   1:[0,3],
//   2:[3],
//   3:[3]
// };

var xScale = d3.scaleLinear()
  .domain([d3.min(thrs[xDim],parseFloat),
           d3.max(thrs[xDim],parseFloat)])
  .range([margin.left, width - margin.right]);

var yScale = d3.scaleLinear()
  .domain([d3.min(thrs[yDim],parseFloat),
           d3.max(thrs[yDim],parseFloat)])
  .range([height - margin.bottom, margin.top]);

var brushX = d3.brushX()
    .extent([[margin.left, 0], [width-margin.right, margin.bottom]])
    .on("end", brushedX),
    
    brushY = d3.brushY()
    .extent([[-margin.left, margin.top], [0, height-margin.bottom]])
    .on("end", brushedY);

var zoom = d3.zoom()
          //.scaleExtent([1, Infinity])
          //.translateExtent([[0,0],[width,height]])
          .on("zoom", zoomed);
var svg = d3.select("body").append("svg")
    .attr("width", width)
    .attr("height", height);

var container = svg.append("g")
        .attr("id","cont")
        //.attr("transform", "translate("+(margin.left)+","+(margin.top)+")")
        .call(zoom);

var xLabel = svg.append("text")
    .attr("id", "xlabel")
    .attr("class", "label")
    .attr("x", width*0.5)
    .attr("y", height-10)
    .attr("stroke", "black")
    .text(function() { return xDim; });
var yLabel = svg.append("text")
    .attr("id", "ylabel")
    .attr("class", "label")
    .attr("transform", "rotate(-90)")
    .attr("x", -width*0.5)
    .attr("y", 15)
    .attr("stroke", "black")
    .text(function() { return yDim; });

var bottomPanel = svg.append("g")
    .attr("id", "bPanel")
    .attr("class", "panel")
    .attr("transform", "translate("+(0)+","+(height-margin.bottom)+")");
    
var xAxis = d3.axisBottom(xScale);
var gX = bottomPanel.append("g")
    .attr("id", "xAxis")
    .attr("class", "axis")
    .call(xAxis); // Create an axis component with d3.axisBottom
var gBX = bottomPanel.append("g")
    .attr("id", "xBrush")
    .attr("class", "brush")
    .call(brushX);
    
var leftPanel = svg.append("g")
    .attr("id", "lPanel")
    .attr("class", "panel")
    .attr("transform", "translate("+margin.left+","+0+")");

var yAxis = d3.axisLeft(yScale);
var gY = leftPanel.append("g")
    .attr("id", "yAxis")
    .attr("class", "axis")
    .call(yAxis); // Create an axis component with d3.axisLeft
var gBY = leftPanel.append("g")
    .attr("id", "xBrush")
    .attr("class", "brush")
    .call(brushY);

compute_projection();
draw();

// ################# definitions of functions #################
    
function compute_projection() {
  projdata = [];

  if (sel_result_data_transposed.length > 0) {
    //var param_ids = sel_result_data_transposed[1];
    var param_ids = [...new Set(sel_result_data_transposed[1])]
    var param_sets = param_ids.map(x => window.result.params[x])
    
    if(d3.select("#param_id").property("value") == "all") {
      for(var p=0, len=param_sets.length; p<len; ++p) {
        const param_id = param_ids[p];
        const param_set = param_sets[p];
        var data = [];
        for(var i=0, len2=param_set.length; i<len2; ++i) {
          var interval = param_set[i];
          var shown = true;
          var par_id = 0;
          while(shown && par_id < param_bounds.length) {
            const bound = param_bounds[par_id];
            if(bound !== null && (d3.min(interval[par_id]) > bound || d3.max(interval[par_id]) < bound)) shown = false;
            par_id++;
          }
          if(shown) data.push({
            x: interval[xDim_id],
            y: interval[yDim_id],
          })
        }
        if(data.length > 0) {
          projdata.push({
            "data": data,
            "id": param_id,
            "cov": sel_result_data_transposed[1].filter( x => x == param_id ).length
          })
        }
      }
    } else {
      const p = d3.select("#param_id").property("value");
      const param_set = window.result.params[p];
  
      var data = [];
      for(var i=0, len2=param_set.length; i<len2; ++i) {
        var interval = param_set[i];
        var shown = true;
        var par_id = 0;
        while(shown && par_id < param_bounds.length) {
          const bound = param_bounds[par_id];
          if(bound !== null && (interval[par_id][0] > bound || interval[par_id][1] < bound)) shown = false;
          par_id++;
        }
        if(shown) data.push({
          x: interval[xDim_id],
          y: interval[yDim_id],
        })
      }
      if(data.length > 0) {
        projdata.push({
          "data": data,
          "id": p,
          "cov": sel_result_data_transposed[1].filter( x => x == p ).length
        })
      }
    }
  }
  console.log(projdata);
}

function update_axes() {
  // Update axes labels according to selected diemnsions
  d3.select('#xlabel').text(xDim);
  d3.select('#ylabel').text(yDim);
  // Update scales according to selected diemnsions
  xScale.domain([d3.min(thrs[xDim],parseFloat),
                 d3.max(thrs[xDim],parseFloat)])

  yScale.domain([d3.min(thrs[yDim],parseFloat),
                 d3.max(thrs[yDim],parseFloat)])
  // Update an axis component according to selected dimensions
  xAxis = d3.axisBottom(xScale);
  gX.call(xAxis);
  yAxis = d3.axisLeft(yScale);
  gY.call(yAxis);
  // reset brushes
  gBX.call(brushX.move, null);
  gBY.call(brushY.move, null);
}
function resettedClick() {
}
function resettedZoom() {
  update_axes()
  container.transition()
      .duration(500)
      .call(zoom.transform, d3.zoomIdentity);
}
function zoomed() {
  if(d3.event.transform) zoomObject = d3.event.transform;
  x = zoomObject.rescaleX(xScale);
  y = zoomObject.rescaleY(yScale);
  
  d3.selectAll(".interval")
  .attr("d", d => {
    var path = "";
    for(var i=0, len=d.data.length; i<len; ++i) {
      var r = d.data[i];
      path += " M"+x(r.x[0])+" "+y(r.y[0])+" H"+x(r.x[1])+" V"+y(r.y[1])+" H"+x(r.x[0])+" z"
    };
    return path;
  })
  
  gX.call(xAxis.scale(x));
  gY.call(yAxis.scale(y));
  // reset brushes
  gBX.call(brushX.move, null);
  gBY.call(brushY.move, null);
}
function brushedX() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(xAxis.scale().invert);
  // TODO: set up brush.move for scale over some threshold (similar to zoom.scaleExtent([1, 100000]) ) to force it to resize along that threshold
  // TODO: implement own control over zoom extent because with embeded functions either it's not possible to move or unzoome after brush or
  //       it's possible to zoom out into a point
  
  scale = xScale.copy().domain(domain);
  range = scale.range().map(x => zoomObject.applyX(x));
  domain = range.map(scale.invert);
  xScale.domain(domain);
  
  zoomed();
}
function brushedY() {
  if (!d3.event.sourceEvent) return; // Only transition after input.
  if (!d3.event.selection) return; // Ignore empty selections.
  var sel = d3.event.selection;
  var domain = sel.map(yAxis.scale().invert);
  
  scale = yScale.copy().domain(domain.reverse());
  range = scale.range().map(y => zoomObject.applyY(y));
  domain = range.map(scale.invert);
  yScale.domain(domain);
  
  zoomed();
}
function fill_info_panel(d) {
}
function handleMouseOver(d, i) {
  var div = document.getElementById("infoPanel");
  var mouse = d3.mouse(this);
  mouse = [zoomObject.rescaleX(xScale).invert(mouse[0]), zoomObject.rescaleY(yScale).invert(mouse[1])];
  var p_count = 0,
      s_count = 0,
      content = "";
      
  if(d3.select(this).attr("class") == "interval") {
    for(var i=0, len=projdata.length; i < len; ++i) {
      var pset = projdata[i];
      for(var j=0, len2=pset.data.length; j < len2; ++j) {
        const par = pset.data[j];
        if(mouse[0] > par.x[0] && mouse[0] < par.x[1] && mouse[1] > par.y[0] && mouse[1] < par.y[1]) {
          p_count++;
          s_count += pset.cov;
          break;
        }
      }
    }
  }
  
  content += "States covered: "+s_count;
  content += "\nParametrisations covered: "+p_count;
  for(var v = 0, len = window.bio.params.length; v < len; ++v) {
    var key = window.bio.params[v];
    content += "\n"+key[0]+": "+(key[0] == xDim ? mouse[0].toFixed(4) : 
                                  (key[0] == yDim ? mouse[1].toFixed(4) : 
                                    (d3.select("#checkbox_"+key[0]).property("checked") ? "["+key[1]+"-"+key[2]+"]" :
                                      d3.select("#slider_"+key[0]).property("value"))));
  }
  
  div.value = content;
}
function fill_info_panel_outside() {
}
function handleMouseOut(d, i) {
  var div = document.getElementById("infoPanel");
  var p_count = 0,
      s_count = 0,
      content = "";
      
  content += "States covered: "+s_count;
  content += "\nParametrisations covered: "+p_count;
  for(var v = 0, len = window.bio.params.length; v < len; ++v) {
    var key = window.bio.params[v];
    content += "\n"+key[0]+": "+(key[0] == xDim ? "["+zoomObject.rescaleX(xScale).domain()[0].toFixed(4)+"-"+zoomObject.rescaleX(xScale).domain()[1].toFixed(4)+"]" : 
                                  (key[0] == yDim ? "["+zoomObject.rescaleY(yScale).domain()[0].toFixed(4)+"-"+zoomObject.rescaleY(yScale).domain()[1].toFixed(4)+"]" : 
                                    (d3.select("#checkbox_"+key[0]).property("checked") ? "["+key[1]+"-"+key[2]+"]" :
                                      d3.select("#slider_"+key[0]).property("value"))));
  }
  
  div.value = content;
}
function handleMouseClick(d, i) {
  
  d3.select("#zoomField").moveUp();
}

function draw() {
  container.select("#zoomField").remove();
  container.selectAll(".interval").remove();
  
  container.append("rect")
    .attr("id", "zoomField")
    .attr("x", margin.left)
    .attr("y", margin.top)
    .attr("width", width-margin.right-margin.left)
    .attr("height", height-margin.bottom-margin.top)
    .attr("fill", "none")
    .on("click", handleMouseClick)
    .on("mousemove", handleMouseOver)
    .on("mouseout", handleMouseOut);
  
  var max_cov = d3.sum(projdata.map(x => x.cov));
  console.log("# "+(projdata.length)+", max coverage: "+max_cov);
  
  container.selectAll(".interval")
    .data(projdata)
    .enter()
    .append("path")
    .attr("class", "interval")
    .attr("id", d => d.id)
    .attr("d", d => {
      var path = "";
      for(var i=0, len=d.data.length; i<len; ++i) {
        var r = d.data[i];
        // Y scale is inverted, therefore, we use the the higher threshold as the first one and the lower threshold as the second one
        path += " M"+zoomObject.rescaleX(xScale)(r.x[0])+","+zoomObject.rescaleY(yScale)(r.y[1])+" H"+zoomObject.rescaleX(xScale)(r.x[1])+" V"+zoomObject.rescaleY(yScale)(r.y[0])+" H"+zoomObject.rescaleX(xScale)(r.x[0])
      }
      return path;
    })
    .attr("fill", reachColor)
    .attr("fill-opacity", d => ""+(d.cov/max_cov))
    .attr("stroke", "none")
    .attr("stroke-width", normalStrokeWidth)
    .attr("pointed", false)
    .on("click", handleMouseClick)
    .on("mousemove", handleMouseOver)
    .on("mouseout", handleMouseOut);
}

    </script>
  </body>

</html>
