$input a_position, a_normal
$output v_color0

/*
 * Copyright 2011-2024 Branimir Karadzic. All rights reserved.
 * License: https://github.com/bkaradzic/bgfx/blob/master/LICENSE
 */

#include <bgfx_shader.sh>

void main()
{
  // Transform vertex position
  gl_Position = mul(u_modelViewProj, vec4(a_position, 1.0));
  vec3 u_lightDir = vec3(0.577, 0.577, 0.577); // Example light direction

  // Simple diffuse lighting calculation:
  float diffuse = max(dot(a_normal, u_lightDir), 0.0);

  // Apply diffuse lighting to the vertex color
  v_color0 = vec4(1.0, 0.0, 0.0, 1.0) * diffuse;
}
