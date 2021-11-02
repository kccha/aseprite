// Aseprite
// Copyright (C) 2001-2018  David Capello
//
// This program is distributed under the terms of
// the End-User License Agreement for Aseprite.

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "app/cmd/set_layer_animation_group.h"

#include "app/doc.h"
#include "app/doc_event.h"
#include "doc/layer.h"
#include "doc/sprite.h"

namespace app {
namespace cmd {

SetLayerAnimationGroup::SetLayerAnimationGroup(Layer* layer, const std::string& name)
  : WithLayer(layer)
  , m_oldAnimationGroup(layer->name())
  , m_newAnimationGroup(name)
{
}

void SetLayerAnimationGroup::onExecute()
{
  layer()->setAnimationGroup(m_newAnimationGroup);
  layer()->incrementVersion();
}

void SetLayerAnimationGroup::onUndo()
{
  layer()->setAnimationGroup(m_oldAnimationGroup);
  layer()->incrementVersion();
}

void SetLayerAnimationGroup::onFireNotifications()
{
  Layer* layer = this->layer();
  Doc* doc = static_cast<Doc*>(layer->sprite()->document());
  DocEvent ev(doc);
  ev.sprite(layer->sprite());
  ev.layer(layer);
  doc->notify_observers<DocEvent&>(&DocObserver::onLayerAnimationGroupChange, ev);
}

} // namespace cmd
} // namespace app
