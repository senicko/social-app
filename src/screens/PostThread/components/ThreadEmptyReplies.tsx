import {View} from 'react-native'
import {Trans} from '@lingui/react/macro'

import {atoms as a, useTheme} from '#/alf'
import {Mark as Logo} from '#/components/icons/Logo'
import {Text} from '#/components/Typography'

/**
 * Centered empty state for a post thread with no replies. Fills the leftover
 * space under the anchor so the butterfly sits in the middle of that area.
 */
export function ThreadEmptyReplies({height}: {height: number}) {
  const t = useTheme()
  const muted = t.atoms.text_contrast_low.color

  return (
    <View
      testID="threadEmptyReplies"
      style={[a.w_full, a.align_center, a.justify_center, a.px_lg, {height}]}>
      <Logo width={88} height={88} fill={muted} />
      <Text
        style={[
          a.mt_md,
          a.text_md,
          a.leading_snug,
          a.text_center,
          {color: muted},
        ]}>
        <Trans>You can be first to comment</Trans>
      </Text>
    </View>
  )
}
